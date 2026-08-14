import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';

import '../../engine/source_edit.dart';
import '../transformation.dart';

/// Forwards constructor parameters straight to the superclass with `super.x`.
///
///     MyWidget({Key? key}) : super(key: key);  ->  MyWidget({super.key});
///
/// Folded only when:
///   * the value reaches `super(...)` as a bare identifier, not an expression
///     like `key ?? const Key()`;
///   * the parameter is used exactly once, in that forward;
///   * for a named argument, the names already match, since renaming would
///     change the constructor's public API;
///   * there is no local default value, which could differ from the super's.
///
/// The type is dropped only when it is identical to the super parameter's, which
/// `super.x` then infers. If every argument is forwarded the `: super(...)` goes
/// away; otherwise the rest stay.
final class SuperParameters implements Transformation {
  const SuperParameters({required this.enabled});

  @override
  final bool enabled;

  @override
  String get name => 'super-parameters';

  @override
  Future<List<SourceEdit>> editsFor(ResolvedUnitResult unit) async {
    final visitor = _SuperParameterVisitor(unit.content);
    unit.unit.accept(visitor);
    return visitor.edits;
  }
}

/// A parameter whose declaration and forwarding argument can collapse to
/// `super.<name>`.
class _Fold {
  _Fold({required this.param, required this.argument, required this.dropType});

  final RegularFormalParameter param;

  /// The argument in the `super(...)` call that forwards [param].
  final Argument argument;

  /// Whether the explicit type is redundant and may be dropped.
  final bool dropType;
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

class _SuperParameterVisitor extends RecursiveAstVisitor<void> {
  _SuperParameterVisitor(this.source);

  final String source;

  final edits = <SourceEdit>[];

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    _collect(node);
    super.visitConstructorDeclaration(node);
  }

  void _collect(ConstructorDeclaration node) {
    // Factory constructors redirect; they have no super initializer to fold.
    if (node.factoryKeyword != null) return;

    SuperConstructorInvocation? superCall;
    for (final initializer in node.initializers) {
      if (initializer is SuperConstructorInvocation) {
        superCall = initializer;
        break;
      }
    }
    if (superCall == null) return;

    // This constructor's formal parameters, indexed by their element so a
    // forwarding identifier can be resolved back to its declaration.
    final paramByElement = <Element, FormalParameter>{};
    for (final param in node.parameters.parameters) {
      final element = param.declaredFragment?.element;
      if (element != null) paramByElement[element] = param;
    }
    if (paramByElement.isEmpty) return;

    // How often each parameter is referenced anywhere in the constructor.
    // A foldable parameter appears exactly once: as the forwarded argument.
    final counter = _ReferenceCounter(paramByElement.keys.toSet());
    node.accept(counter);

    final arguments = superCall.argumentList.arguments;
    final folds = <_Fold>[];
    for (final argument in arguments) {
      final fold = _tryFold(argument, paramByElement, counter.counts);
      if (fold != null) folds.add(fold);
    }
    if (folds.isEmpty) return;

    for (final fold in folds) {
      edits.add(_rewriteParameter(fold));
    }

    if (folds.length == arguments.length) {
      edits.add(_removeSuperCall(node, superCall));
    } else {
      edits.add(_keepRemainingArguments(superCall, folds));
    }
  }

  /// Rebuilds the `super(...)` argument list with only the unfolded arguments,
  /// for the case where some, but not all, arguments are forwarded.
  SourceEdit _keepRemainingArguments(
    SuperConstructorInvocation superCall,
    List<_Fold> folds,
  ) {
    final folded = {for (final fold in folds) fold.argument};
    final kept = [
      for (final argument in superCall.argumentList.arguments)
        if (!folded.contains(argument))
          source.substring(argument.offset, argument.end),
    ];
    final left = superCall.argumentList.leftParenthesis;
    final right = superCall.argumentList.rightParenthesis;
    return .new(
      offset: left.end,
      length: right.offset - left.end,
      replacement: kept.join(', '),
    );
  }

  /// Removes the entire `super(...)` initializer once every argument is folded.
  SourceEdit _removeSuperCall(
    ConstructorDeclaration node,
    SuperConstructorInvocation superCall,
  ) {
    final initializers = node.initializers;
    if (initializers.length == 1) {
      // Drop ` : super(...)` from just after the parameter list.
      final start = node.parameters.rightParenthesis.end;
      return .new(
        offset: start,
        length: superCall.end - start,
        replacement: '',
      );
    }

    final index = initializers.indexOf(superCall);
    if (index > 0) {
      // Drop ", super(...)" together with the comma before it.
      final start = initializers[index - 1].end;
      return .new(
        offset: start,
        length: superCall.end - start,
        replacement: '',
      );
    }
    // First of several: drop "super(...), " up to the next initializer.
    final end = initializers[index + 1].offset;
    return .new(
      offset: superCall.offset,
      length: end - superCall.offset,
      replacement: '',
    );
  }

  /// Replaces a `Type name` declaration with `super.name`, dropping the type
  /// only when it is redundant.
  SourceEdit _rewriteParameter(_Fold fold) {
    final name = fold.param.name!;
    final type = fold.param.type;
    final start = (fold.dropType && type != null) ? type.offset : name.offset;
    return .new(
      offset: start,
      length: name.end - start,
      replacement: 'super.${name.lexeme}',
    );
  }

  /// Returns a [_Fold] when [argument] forwards one of [paramByElement]
  /// unchanged and that parameter is used nowhere else, or null otherwise.
  _Fold? _tryFold(
    Argument argument,
    Map<Element, FormalParameter> paramByElement,
    Map<Element, int> counts,
  ) {
    final superParam = argument.correspondingParameter;
    if (superParam == null) return null;

    // The value must reach super verbatim: a bare reference, not an expression.
    final expression = argument.argumentExpression;
    if (expression is! SimpleIdentifier) return null;
    final referenced = expression.element;
    if (referenced == null) return null;

    final param = paramByElement[referenced];
    // Only plain `Type name` parameters fold; `this.x`, an existing `super.x`,
    // or a function-typed parameter are out of scope.
    if (param is! RegularFormalParameter) return null;
    if (param.name == null) return null;
    if (param.functionTypedSuffix != null) return null;
    if (param.constFinalOrVarKeyword != null) return null;
    if (param.covariantKeyword != null) return null;

    // A local default could differ from the super's; keep the explicit forward.
    if (param.defaultClause != null) return null;

    // Used only as the forward; never read, reassigned, or used elsewhere.
    if ((counts[referenced] ?? 0) != 1) return null;

    // For a named argument, folding to `super.<label>` renames the parameter
    // unless its local name already matches the super parameter's name.
    if (argument is NamedArgument) {
      final label = argument.name.lexeme;
      if (param.name!.lexeme != label) return null;
      if (superParam.name != label) return null;
    }

    final localType = param.declaredFragment?.element.type;
    final dropType = localType != null && localType == superParam.type;

    return .new(param: param, argument: argument, dropType: dropType);
  }
}
