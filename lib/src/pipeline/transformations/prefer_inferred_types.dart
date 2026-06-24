import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/type.dart';

import '../../engine/source_edit.dart';
import '../transformation.dart';

/// Removes a redundant explicit type annotation when the initializer's
/// inferred static type is exactly the declared type.
///
/// Before:
///   final String name = 'hello';         // local final
///   const int n = 0;                     // local const
///   Foo f = Foo();                        // bare-typed local  → var f = Foo()
///   static const String a = 'aaa';      // static const field
///   const int b = 4;                     // top-level const
///
/// After:
///   final name = 'hello';
///   const n = 0;
///   var f = Foo();
///   static const a = 'aaa';
///   const b = 4;
///
/// A type annotation is dropped only when ALL of the following hold:
///   * The initializer's static type equals the declared type exactly:
///     same interface element, same type arguments (recursively), same
///     nullability.
///   * The declared type is not dynamic (dynamic is never an InterfaceType,
///     so the strict same-type check already rejects it).
///   * The initializer is not a collection literal without explicit type
///     arguments (removing the annotation would change the inferred element
///     type via downward inference, e.g. `[]` → `List<dynamic>`).
///   * The initializer is not a null literal (whose type is Null, not the
///     declared nullable type).
///
/// Scope:
///   * LOCAL variables: final, const, or bare-typed (no keyword). Bare-typed
///     locals become `var` so that `final_locals` can then upgrade them on the
///     next run.
///   * CONST declarations anywhere: local const, top-level const, and
///     `static const` class fields.
///
/// Non-const class fields and non-const top-level variables are intentionally
/// left untouched: Effective Dart recommends annotating these, and their
/// inference can depend on complex initializers.
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
    if (node.isStatic && node.fields.isConst) {
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
      // final/const: remove type token and the whitespace before the name.
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
      // Bare-typed local (no keyword): replace the type with `var`.
      edits.add(
        SourceEdit(
          offset: typeAnnotation.offset,
          length: typeAnnotation.length,
          replacement: 'var',
        ),
      );
    }
  }

  void _collect(VariableDeclarationList vars, {required bool isLocal}) {
    final typeAnnotation = vars.type;
    if (typeAnnotation == null) return;

    final declaredType = typeAnnotation.type;
    if (declaredType == null) return;

    // Only allow final/const or bare-typed (null keyword) for locals.
    // For non-local, caller guarantees isConst, keyword is const.
    if (isLocal && vars.keyword?.lexeme == 'var') return;

    for (final varDecl in vars.variables) {
      final initializer = varDecl.initializer;
      if (initializer == null) return;
      if (_isUnsafeInitializer(initializer, declaredType)) return;

      final inferredType = initializer.staticType;
      if (inferredType == null) return;
      if (!_sameType(declaredType, inferredType)) return;
    }

    _applyEdit(vars);
  }

  /// Returns true for initializers whose inferred type depends on the declared
  /// type as downward context. Removing the annotation would silently change
  /// the inferred type.
  bool _isUnsafeInitializer(Expression expr, DartType declaredType) {
    if (expr is ListLiteral && expr.typeArguments == null) return true;
    if (expr is SetOrMapLiteral && expr.typeArguments == null) return true;
    if (expr is NullLiteral) return true;
    // Integer literals are implicitly promoted to double in a double-typed
    // context: the analyzer reports staticType=double for `3` when the declared
    // type is double. Removing the annotation would revert the inferred type to
    // int, so only trust the match when the declared type is exactly int.
    if (expr is IntegerLiteral && declaredType is InterfaceType) {
      if (declaredType.element.name != 'int') return true;
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
}
