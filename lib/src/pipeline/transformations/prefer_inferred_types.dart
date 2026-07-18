import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/type.dart';

import '../../engine/source_edit.dart';
import '../transformation.dart';

/// Removes or relocates redundant explicit type annotations.
///
/// Rule A (drop): removes the annotation when the initializer's static type
/// exactly equals the declared type (same element, type arguments, nullability)
/// *and* that type is obvious from the initializer's own syntax. Bare-typed
/// locals become `var` so `final_locals` can upgrade them.
///
/// A type is "obvious" in the sense the analyzer uses for its
/// `omit_obvious_*` / `specify_nonobvious_*` rules: a literal, an
/// explicitly-typed collection literal, a constructor call whose type is spelled
/// out (`Foo()`, `Foo<int>()`, `Foo.named()`), a cast, or a cascade/prefix over
/// one of these. A non-obvious initializer (a method call, property access, bare
/// identifier, or a generic constructor with inferred type arguments) keeps its
/// annotation: dropping it would trip `specify_nonobvious_*`, which `dart fix`
/// (the fix-all pass) then reverts, so the tool would disagree with itself
/// between a `--no-fix-all` run and a full run.
///
/// Rule B (relocate): when the initializer is a bare collection literal without
/// explicit type arguments and the declared type is exactly `List`, `Set`, or
/// `Map` from dart:core (non-nullable), the type arguments are moved onto the
/// literal and the annotation is removed. Also fires when the bare literal is
/// the cascade target (i.e., after the cascades pass has run).
///
/// Rule C (expand): when the initializer is a dot-shorthand constructor
/// (`.new(...)` / `.named(...)`) whose static type is exactly the declared type,
/// the shorthand is expanded to its explicit form and the annotation is removed,
/// so the type is named once on the initializer instead of twice: a hand-written
/// `final Foo a = .new(x)` becomes `final a = Foo(x)`, and
/// `late final Foo a = .named()` becomes `late final a = Foo.named()`. The
/// `late` modifier and the `final`/`const`/`var` keyword are left as written.
/// Only a constructor shorthand qualifies; a static-member shorthand (`.zero`,
/// `.parse(...)`) would expand to a non-obvious property or method access that
/// `specify_nonobvious_*` (and fix-all) would re-annotate.
///
/// Scope: local finals/consts/bare-typed, top-level const, and `final`/`const`
/// fields (instance or static) that have an initializer. A `final Foo _x = Foo()`
/// field becomes `final _x = Foo()`, which is preferred over the `.new()`
/// shorthand dot-shorthands would otherwise emit. Mutable fields and non-const
/// top-level variables are left untouched.
final class PreferInferredTypes implements Transformation {
  const PreferInferredTypes({required this.enabled});

  @override
  final bool enabled;

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
  _PreferInferredTypesVisitor(this.source);
  final String source;

  final edits = <SourceEdit>[];

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
        .new(
          offset: typeAnnotation.offset,
          length: typeAnnotation.length + wsLength,
          replacement: '',
        ),
      );
    } else {
      edits.add(
        .new(
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

    // Rule A: drop when every initializer's static type equals declared and is
    // obvious from the initializer, so the removal never introduces a
    // `specify_nonobvious_*` diagnostic that fix-all would revert.
    var ruleAApplies = true;
    for (final varDecl in vars.variables) {
      final expr = varDecl.initializer!;
      if (_isUnsafeInitializer(expr, declaredType) || !_hasObviousType(expr)) {
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

    // Rules B and C both rewrite the single initializer.
    if (vars.variables.length != 1) return;

    // Rule C: expand a dot-shorthand constructor so the annotation can go.
    if (_tryExpandShorthandConstructor(vars, declaredType, typeAnnotation)) {
      return;
    }

    // Rule B: relocate collection type args onto the literal.
    _tryRelocate(
      vars,
      declaredType,
      typeAnnotation,
      vars.variables.first.initializer!,
    );
  }

  /// Whether the static type of [expr] is obvious from its own syntax, matching
  /// the analyzer's `omit_obvious_*` / `specify_nonobvious_*` rules. Only an
  /// obvious initializer is eligible for Rule A; keeping a non-obvious one
  /// avoids introducing a `specify_nonobvious_*` diagnostic (which fix-all would
  /// then revert on the next run).
  bool _hasObviousType(Expression expr) {
    if (expr is IntegerLiteral ||
        expr is DoubleLiteral ||
        expr is BooleanLiteral ||
        expr is SimpleStringLiteral ||
        expr is AdjacentStrings ||
        expr is StringInterpolation ||
        expr is SymbolLiteral) {
      return true;
    }
    // A collection literal is obvious only with explicit type arguments
    // (`<int>[]`); a bare `[]` is left for Rule B to relocate onto.
    if (expr is TypedLiteral) return expr.typeArguments != null;
    // A cast names its result type outright.
    if (expr is AsExpression) return true;
    // `-1` is obvious; the operand decides.
    if (expr is PrefixExpression) return _hasObviousType(expr.operand);
    // A cascade has the static type of its target.
    if (expr is CascadeExpression) return _hasObviousType(expr.target);
    // `Foo()` / `Foo.named()` / `Foo<int>()` are obvious when the type is
    // non-generic or its type arguments are written explicitly. A generic type
    // with inferred arguments (`Box()` for a `Box<int>` target) is not.
    if (expr is InstanceCreationExpression) {
      final namedType = expr.constructorName.type;
      if (namedType.typeArguments != null) return true;
      final type = namedType.type;
      return type is InterfaceType && type.typeArguments.isEmpty;
    }
    return false;
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
    // A dot shorthand (`.new(...)`, `.named(...)`, `.value`) resolves only
    // against the declared type; dropping the annotation would leave it with no
    // context. (A single run never reaches this, since shorthands are produced
    // later; it guards re-runs and hand-written code.)
    if (expr is DotShorthandInvocation ||
        expr is DotShorthandConstructorInvocation ||
        expr is DotShorthandPropertyAccess) {
      return true;
    }
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

  /// Expands a dot-shorthand constructor initializer to its explicit form and
  /// drops the now-redundant annotation, so `final Foo a = .new(x)` becomes
  /// `final a = Foo(x)` and `late final Foo a = .named()` becomes
  /// `late final a = Foo.named()`. The `late` modifier and the keyword are left
  /// as written. Returns true when it applied.
  ///
  /// Only a constructor shorthand is expanded. A static-member shorthand
  /// (`.parse(...)`, `.zero`) would become a method call or property access
  /// whose type is not obvious, so `specify_nonobvious_*` (and fix-all) would
  /// put the annotation straight back.
  bool _tryExpandShorthandConstructor(
    VariableDeclarationList vars,
    DartType declaredType,
    TypeAnnotation typeAnnotation,
  ) {
    final initializer = vars.variables.first.initializer!;
    if (initializer is! DotShorthandConstructorInvocation) return false;

    // An explicit `<...>` on the shorthand would dangle after the type name is
    // inserted; the annotation carries the type arguments, so require none here.
    if (initializer.typeArguments != null) return false;

    final inferred = initializer.staticType;
    if (inferred == null || !_sameType(declaredType, inferred)) return false;

    // The written type text (with any import prefix and type arguments) is
    // reused verbatim as the constructor's type, so the static type is preserved
    // exactly and the expanded form is obvious (never re-annotated by fix-all).
    if (typeAnnotation is! NamedType) return false;
    final typeText = source.substring(
      typeAnnotation.offset,
      typeAnnotation.end,
    );

    _applyEdit(vars);

    final period = initializer.period;
    final constructorName = initializer.constructorName;
    if (constructorName.name == 'new') {
      // `.new(args)` -> `Foo(args)`: replace `.new` with the written type.
      edits.add(
        .new(
          offset: period.offset,
          length: constructorName.end - period.offset,
          replacement: typeText,
        ),
      );
    } else {
      // `.named(args)` -> `Foo.named(args)`: insert the type before the `.`.
      edits.add(.new(offset: period.offset, length: 0, replacement: typeText));
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
    if (declaredType.nullabilitySuffix != .none) return;

    final literal = _bareCollectionLiteral(initializer);
    if (literal == null) return;

    if (!_isExactCoreCollectionType(declaredType, literal)) return;

    if (typeAnnotation is! NamedType) return;
    final typeArgs = typeAnnotation.typeArguments;
    if (typeArgs == null) return;

    final typeArgsText = source.substring(typeArgs.offset, typeArgs.end);

    _applyEdit(vars);
    edits.add(
      .new(offset: literal.offset, length: 0, replacement: typeArgsText),
    );
  }
}
