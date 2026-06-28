import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';

import '../../engine/source_edit.dart';
import '../transformation.dart';

/// Removes or relocates redundant explicit type annotations.
///
/// Rule A (drop): removes the annotation when the initializer's static type
/// exactly equals the declared type (same element, type arguments, nullability).
/// Bare-typed locals become `var` so `final_locals` can upgrade them.
///
/// Rule B (relocate): when the initializer is a bare collection literal without
/// explicit type arguments and the declared type is exactly `List`, `Set`, or
/// `Map` from dart:core (non-nullable), the type arguments are moved onto the
/// literal and the annotation is removed. Also fires when the bare literal is
/// the cascade target (i.e., after the cascades pass has run).
///
/// Scope: local finals/consts/bare-typed, top-level const, and `final`/`const`
/// fields (instance or static) that have an initializer. A `final Foo _x = Foo()`
/// field becomes `final _x = Foo()`, which is preferred over the `.new()`
/// shorthand dot-shorthands would otherwise emit. Mutable fields and non-const
/// top-level variables are left untouched.
final class PreferInferredTypes implements Transformation {
  @override
  final bool enabled;

  const PreferInferredTypes({required this.enabled});

  @override
  String get name => 'prefer-inferred-types';

  @override
  Future<List<SourceEdit>> editsFor(ResolvedUnitResult unit) async {
    final visitor = _PreferInferredTypesVisitor(unit.content);
    unit.unit.accept(visitor);
    return visitor.edits;
  }
}

class _PreferInferredTypesVisitor extends RecursiveAstVisitor<void> {
  final String source;
  final List<SourceEdit> edits = [];

  _PreferInferredTypesVisitor(this.source);

  @override
  void visitFieldDeclaration(FieldDeclaration node) {
    if (node.fields.isConst || node.fields.isFinal) {
      _collect(node.fields, isLocal: false);
    }
    super.visitFieldDeclaration(node);
  }

  @override
  void visitTopLevelVariableDeclaration(TopLevelVariableDeclaration node) {
    if (node.variables.isConst) _collect(node.variables, isLocal: false);
    super.visitTopLevelVariableDeclaration(node);
  }

  @override
  void visitVariableDeclarationStatement(VariableDeclarationStatement node) {
    _collect(node.variables, isLocal: true);
    super.visitVariableDeclarationStatement(node);
  }

  void _applyEdit(VariableDeclarationList vars) {
    final typeAnnotation = vars.type!;
    final typeEnd = typeAnnotation.end;

    if (vars.keyword != null) {
      var wsLength = 0;
      while (typeEnd + wsLength < source.length &&
          source[typeEnd + wsLength] == ' ') {
        wsLength++;
      }
      edits.add(
        SourceEdit(
          offset: typeAnnotation.offset,
          length: typeAnnotation.length + wsLength,
          replacement: '',
        ),
      );
    } else {
      edits.add(
        SourceEdit(
          offset: typeAnnotation.offset,
          length: typeAnnotation.length,
          replacement: 'var',
        ),
      );
    }
  }

  /// Extracts the bare collection literal from [expr], or null if none.
  /// Looks through a [CascadeExpression] to find a bare literal target.
  Expression? _bareCollectionLiteral(Expression expr) {
    if (expr is ListLiteral && expr.typeArguments == null) return expr;
    if (expr is SetOrMapLiteral && expr.typeArguments == null) return expr;
    if (expr is CascadeExpression) {
      final target = expr.target;
      if (target is ListLiteral && target.typeArguments == null) return target;
      if (target is SetOrMapLiteral && target.typeArguments == null) {
        return target;
      }
    }
    return null;
  }

  void _collect(VariableDeclarationList vars, {required bool isLocal}) {
    final typeAnnotation = vars.type;
    if (typeAnnotation == null) return;

    final declaredType = typeAnnotation.type;
    if (declaredType == null) return;

    if (isLocal && vars.keyword?.lexeme == 'var') return;

    for (final varDecl in vars.variables) {
      if (varDecl.initializer == null) return;
    }

    // Rule A: drop when every initializer's static type equals declared.
    var ruleAApplies = true;
    for (final varDecl in vars.variables) {
      final expr = varDecl.initializer!;
      if (_isUnsafeInitializer(expr, declaredType)) {
        ruleAApplies = false;
        break;
      }
      final inferredType = expr.staticType;
      if (inferredType == null || !_sameType(declaredType, inferredType)) {
        ruleAApplies = false;
        break;
      }
    }
    if (ruleAApplies) {
      _applyEdit(vars);
      return;
    }

    // Rule B: relocate collection type args onto the literal (single-variable only).
    if (vars.variables.length != 1) return;
    _tryRelocate(
      vars,
      declaredType,
      typeAnnotation,
      vars.variables.first.initializer!,
    );
  }

  /// Returns true when [declared] is exactly `List`, `Set`, or `Map` from
  /// dart:core (matched by name), with at least one type argument, and the
  /// literal kind matches (ListLiteral → List, isSet → Set, isMap → Map).
  bool _isExactCoreCollectionType(DartType declared, Expression literal) {
    if (declared is! InterfaceType) return false;
    if (declared.typeArguments.isEmpty) return false;
    final name = declared.element.name;
    if (literal is ListLiteral) return name == 'List';
    if (literal is SetOrMapLiteral) {
      if (literal.isSet) return name == 'Set';
      if (literal.isMap) return name == 'Map';
    }
    return false;
  }

  /// Returns true for initializers whose inferred type depends on the declared
  /// type as downward context. Removing the annotation would silently change
  /// the inferred type. Rule B handles bare collection literals by relocating
  /// the type arguments instead of dropping the annotation.
  bool _isUnsafeInitializer(Expression expr, DartType declaredType) {
    if (expr is ListLiteral && expr.typeArguments == null) return true;
    if (expr is SetOrMapLiteral && expr.typeArguments == null) return true;
    if (expr is NullLiteral) return true;
    if (expr is IntegerLiteral && declaredType is InterfaceType) {
      if (declaredType.element.name != 'int') return true;
    }
    // A cascade whose target is a bare collection literal is unsafe for Rule A.
    if (expr is CascadeExpression) {
      final target = expr.target;
      if (target is ListLiteral && target.typeArguments == null) return true;
      if (target is SetOrMapLiteral && target.typeArguments == null) {
        return true;
      }
    }
    return false;
  }

  /// Returns true when [declared] and [inferred] are the same interface type:
  /// same class element, same nullability, and identical type arguments
  /// (checked recursively).
  bool _sameType(DartType declared, DartType inferred) {
    if (declared is! InterfaceType || inferred is! InterfaceType) return false;
    if (declared.element != inferred.element) return false;
    if (declared.nullabilitySuffix != inferred.nullabilitySuffix) return false;
    final a = declared.typeArguments;
    final b = inferred.typeArguments;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_sameType(a[i], b[i])) return false;
    }
    return true;
  }

  /// Relocates the declared type arguments onto the bare collection literal
  /// and removes the annotation, preserving the static type exactly.
  void _tryRelocate(
    VariableDeclarationList vars,
    DartType declaredType,
    TypeAnnotation typeAnnotation,
    Expression initializer,
  ) {
    if (declaredType.nullabilitySuffix != NullabilitySuffix.none) return;

    final literal = _bareCollectionLiteral(initializer);
    if (literal == null) return;

    if (!_isExactCoreCollectionType(declaredType, literal)) return;

    if (typeAnnotation is! NamedType) return;
    final typeArgs = typeAnnotation.typeArguments;
    if (typeArgs == null) return;

    final typeArgsText = source.substring(typeArgs.offset, typeArgs.end);

    _applyEdit(vars);
    edits.add(
      SourceEdit(offset: literal.offset, length: 0, replacement: typeArgsText),
    );
  }
}
