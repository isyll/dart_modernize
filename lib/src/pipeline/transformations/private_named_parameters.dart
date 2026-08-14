import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';

import '../../engine/source_edit.dart';
import '../transformation.dart';

/// Folds verbose constructor field boilerplate into the private named
/// parameter form (`this._field`).
///
///     C({required String name}) : _name = name;  ->  C({required this._name});
///
/// Folded only when:
///   * the initializer is exactly `_field = param`, with nothing wrapping it;
///   * the parameter is named, not positional;
///   * it is used once, in that initializer;
///   * its name is the field name without the underscore. `this._name` exposes
///     `name`, so any other parameter name would change the public API;
///   * its type matches the field's.
///
/// If every initializer folds, the whole `: ...` list goes away; otherwise the
/// rest are kept as written.
final class PrivateNamedParameters implements Transformation {
  const PrivateNamedParameters({required this.enabled});

  @override
  final bool enabled;

  @override
  String get name => 'private-named-parameters';

  @override
  Future<List<SourceEdit>> editsFor(ResolvedUnitResult unit) async {
    final visitor = _Visitor(unit.content);
    unit.unit.accept(visitor);
    return visitor.edits;
  }
}

class _Fold {
  _Fold({
    required this.param,
    required this.initializer,
    required this.fieldName,
  });
  final RegularFormalParameter param;

  final ConstructorFieldInitializer initializer;

  /// The private field name (e.g. `'_x'`); becomes `this._x` in the output.
  final String fieldName;
}

/// Counts references to a fixed set of parameter elements within a subtree.
class _ReferenceCounter extends RecursiveAstVisitor<void> {
  _ReferenceCounter(this.targets);
  final Set<Element> targets;

  final counts = <Element, int>{};

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    final element = node.element;
    if (element != null && targets.contains(element)) {
      counts[element] = (counts[element] ?? 0) + 1;
    }
    super.visitSimpleIdentifier(node);
  }
}

class _Visitor extends RecursiveAstVisitor<void> {
  _Visitor(this.source);
  final String source;

  final edits = <SourceEdit>[];

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    _collect(node);
    super.visitConstructorDeclaration(node);
  }

  void _collect(ConstructorDeclaration node) {
    if (node.factoryKeyword != null) return;

    final initializers = node.initializers;
    if (initializers.isEmpty) return;

    final constructorElem = node.declaredFragment?.element;
    if (constructorElem == null) return;
    final classElem = constructorElem.enclosingElement;

    // Parameter element -> its formal-parameter AST node.
    final paramByElement = <Element, FormalParameter>{};
    for (final param in node.parameters.parameters) {
      final element = param.declaredFragment?.element;
      if (element != null) paramByElement[element] = param;
    }
    if (paramByElement.isEmpty) return;

    // Count how many times each parameter element appears anywhere in the
    // constructor (body + entire initializer list).
    final counter = _ReferenceCounter(paramByElement.keys.toSet());
    node.accept(counter);

    final folds = <_Fold>[];
    for (final initializer in initializers) {
      if (initializer is! ConstructorFieldInitializer) continue;
      final fold = _tryFold(
        initializer,
        paramByElement,
        counter.counts,
        classElem,
      );
      if (fold != null) folds.add(fold);
    }
    if (folds.isEmpty) return;

    for (final fold in folds) {
      edits.add(_rewriteParam(fold));
    }

    final foldedSet = {for (final fold in folds) fold.initializer};
    if (foldedSet.length == initializers.length) {
      // Remove the entire `: init1, init2, …` suffix.
      final start = node.parameters.rightParenthesis.end;
      edits.add(
        .new(
          offset: start,
          length: initializers.last.end - start,
          replacement: '',
        ),
      );
    } else {
      // Reconstruct the initializer list with only the unfolded entries.
      final kept = [
        for (final init in initializers)
          if (!foldedSet.contains(init))
            source.substring(init.offset, init.end),
      ];
      final start = node.parameters.rightParenthesis.end;
      edits.add(
        .new(
          offset: start,
          length: initializers.last.end - start,
          replacement: ' : ${kept.join(', ')}',
        ),
      );
    }
  }

  /// Replaces `Type name` in the parameter list with `this._fieldName`.
  ///
  /// The `required` keyword (if any) and any default value (if any) are
  /// preserved because they fall outside the replaced range.
  SourceEdit _rewriteParam(_Fold fold) {
    final name = fold.param.name!;
    final type = fold.param.type;
    final start = type?.offset ?? name.offset;
    return .new(
      offset: start,
      length: name.end - start,
      replacement: 'this.${fold.fieldName}',
    );
  }

  _Fold? _tryFold(
    ConstructorFieldInitializer initializer,
    Map<Element, FormalParameter> paramByElement,
    Map<Element, int> counts,
    InterfaceElement classElem,
  ) {
    final fieldName = initializer.fieldName.name;
    if (!fieldName.startsWith('_')) return null;

    // The assigned value must be a bare reference : no expression wrapping.
    final expression = initializer.expression;
    if (expression is! SimpleIdentifier) return null;
    final referenced = expression.element;
    if (referenced == null) return null;

    final param = paramByElement[referenced];
    // Only plain `Type name` parameters fold; this.x, super.x, and
    // function-typed parameters are out of scope.
    if (param is! RegularFormalParameter) return null;
    if (param.name == null) return null;
    if (param.functionTypedSuffix != null) return null;
    if (param.constFinalOrVarKeyword != null) return null;
    if (param.covariantKeyword != null) return null;

    // Positional parameters are out of scope; only named `{…}` params fold.
    final paramElem = param.declaredFragment?.element;
    if (paramElem == null || !paramElem.isNamed) return null;

    // `this._name` derives the public parameter name `name` (underscore
    // stripped). The fold is API-preserving only when the current parameter
    // name already matches.
    if (param.name!.lexeme != fieldName.substring(1)) return null;

    // The parameter must appear only in this one initializer; any additional
    // reference (body use, other initializer) makes the fold unsafe.
    if ((counts[referenced] ?? 0) != 1) return null;

    // Types must be identical so `this._field` infers the same static type.
    final paramType = paramElem.type;
    final fieldType = classElem.getField(fieldName)?.type;
    if (fieldType == null || paramType != fieldType) return null;

    return .new(param: param, initializer: initializer, fieldName: fieldName);
  }
}
