import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

import '../../engine/source_edit.dart';
import '../transformation.dart';

/// Inlines a local variable that is declared, immediately returned, and used
/// nowhere else.
///
/// Before:
///   final x = compute();
///   return x;
///
/// After:
///   return compute();
///
/// The rewrite is applied only when ALL of the following hold:
///   * the declaration has exactly one variable with an initializer;
///   * the statement immediately following it is `return <thatLocal>;` -- a bare
///     return of the local, not `return f(x);` or `return x + 1;`;
///   * the local is used nowhere else in the enclosing block;
///   * no comment is attached to the declaration or sits between it and the
///     return that would be lost by removing the declaration line;
///   * the initializer infers the same type in the `return`. Moving it there
///     changes its context type, from none (or the declared type) to the
///     return type, `FutureOr<T>` in an `async` body. An initializer whose
///     inference reads that context (a generic call without `<...>`, a
///     collection literal without type arguments, a closure, an integer
///     literal, a dot shorthand, a switch expression) is only moved when the
///     local's type is exactly the function's declared return type, or `T`
///     for an `async` function returning `Future<T>`. In an `async` body a
///     generic call or a closure is never moved: inference can pick
///     `FutureOr<T>` for its type argument there;
///   * the initializer is not `dynamic` assigned to a typed local, whose
///     implicit cast the move would drop.
final class InlineReturn implements Transformation {
  const InlineReturn({required this.enabled});

  @override
  final bool enabled;

  @override
  String get name => 'inline-return';

  @override
  Future<List<SourceEdit>> editsFor(ResolvedUnitResult unit) async {
    final visitor = _InlineReturnVisitor(unit.content);
    unit.unit.accept(visitor);
    return visitor.edits;
  }
}

class _InlineReturnVisitor(final String source)
    extends RecursiveAstVisitor<void> {
  final edits = <SourceEdit>[];

  @override
  void visitBlock(Block node) {
    _collect(node.statements);
    super.visitBlock(node);
  }

  void _collect(NodeList<Statement> statements) {
    for (var i = 0; i < statements.length - 1; i++) {
      final decl = statements[i];
      if (decl is! VariableDeclarationStatement) continue;

      final vars = decl.variables;
      if (vars.variables.length != 1) continue;

      final varDecl = vars.variables.single;
      if (varDecl.initializer == null) continue;

      final element = varDecl.declaredFragment?.element;
      if (element == null) continue;

      final next = statements[i + 1];
      if (next is! ReturnStatement) continue;
      final returnExpr = next.expression;
      if (returnExpr is! SimpleIdentifier) continue;
      if (returnExpr.element != element) continue;

      if (_isReferencedElsewhere(element, statements, i)) continue;
      if (_hasComment(decl, next)) continue;
      if (!_keepsItsType(vars, varDecl, next)) continue;

      edits.add(
        .new(
          offset: decl.offset,
          length: next.end - decl.offset,
          replacement:
              'return ${source.substring(varDecl.initializer!.offset, varDecl.initializer!.end)};',
        ),
      );
    }
  }

  /// Whether [initializer] infers the same type as the value of [returnStmt]
  /// as it did as the initializer of [vars]. See the class comment.
  bool _keepsItsType(
    VariableDeclarationList vars,
    VariableDeclaration variable,
    ReturnStatement returnStmt,
  ) {
    final initializer = variable.initializer!;
    final declared = vars.type?.type;
    if (declared != null &&
        declared is! DynamicType &&
        initializer.staticType is DynamicType) {
      return false;
    }
    if (!_dependsOnContext(initializer)) return true;

    final localType = variable.declaredFragment?.element.type;
    final body = returnStmt.thisOrAncestorOfType<FunctionBody>();
    if (localType == null || body == null || body.isGenerator) return false;
    final owner = body.parent;
    final DartType? returnType = switch (owner) {
      MethodDeclaration() => owner.returnType?.type,
      FunctionExpression() => switch (owner.parent) {
        FunctionDeclaration(:final returnType) => returnType?.type,
        _ => null,
      },
      _ => null,
    };
    if (returnType == null) return false;
    if (!body.isAsynchronous) return returnType == localType;

    // The context of an async return value is `FutureOr<T>`.
    return returnType is InterfaceType &&
        returnType.isDartAsyncFuture &&
        returnType.typeArguments.length == 1 &&
        returnType.typeArguments.single == localType &&
        !_infersFromFutureOr(initializer);
  }

  /// Whether a generic call without `<...>` or a closure takes its type from
  /// the context of [expression], where a `FutureOr<T>` context can make it
  /// infer `FutureOr<T>` instead of `T`. Collection literals and dot
  /// shorthands look through `FutureOr`, so they are fine.
  bool _infersFromFutureOr(Expression expression) => switch (expression) {
    FunctionExpression() => true,
    ParenthesizedExpression(:final expression) => _infersFromFutureOr(
      expression,
    ),
    AwaitExpression(:final expression) => _infersFromFutureOr(expression),
    CascadeExpression(:final target) => _infersFromFutureOr(target),
    ConditionalExpression(:final thenExpression, :final elseExpression) =>
      _infersFromFutureOr(thenExpression) ||
          _infersFromFutureOr(elseExpression),
    BinaryExpression(:final operator, :final leftOperand, :final rightOperand)
        when operator.lexeme == '??' =>
      _infersFromFutureOr(leftOperand) || _infersFromFutureOr(rightOperand),
    SwitchExpression(:final cases) => cases.any(
      (c) => _infersFromFutureOr(c.expression),
    ),
    InstanceCreationExpression() ||
    MethodInvocation() ||
    FunctionExpressionInvocation() => _dependsOnContext(expression),
    _ => false,
  };

  /// Whether inferring [expression] reads its context type.
  bool _dependsOnContext(Expression expression) => switch (expression) {
    IntegerLiteral() => true,
    TypedLiteral(:final typeArguments) => typeArguments == null,
    RecordLiteral(:final fields) => fields.any(
      (field) => _dependsOnContext(field.fieldExpression),
    ),
    FunctionExpression() => true,
    DotShorthandInvocation() ||
    DotShorthandPropertyAccess() ||
    DotShorthandConstructorInvocation() => true,
    ParenthesizedExpression(:final expression) => _dependsOnContext(expression),
    PrefixExpression(:final operand) => _dependsOnContext(operand),
    AwaitExpression(:final expression) => _dependsOnContext(expression),
    CascadeExpression(:final target) => _dependsOnContext(target),
    ConditionalExpression(:final thenExpression, :final elseExpression) =>
      _dependsOnContext(thenExpression) || _dependsOnContext(elseExpression),
    BinaryExpression(:final operator, :final leftOperand, :final rightOperand)
        when operator.lexeme == '??' =>
      _dependsOnContext(leftOperand) || _dependsOnContext(rightOperand),
    SwitchExpression() => true,
    InstanceCreationExpression(:final constructorName) =>
      constructorName.type.typeArguments == null &&
          (constructorName
                  .element
                  ?.enclosingElement
                  .typeParameters
                  .isNotEmpty ??
              false),
    MethodInvocation(:final typeArguments, :final methodName) =>
      typeArguments == null &&
          switch (methodName.element) {
            ExecutableElement(:final typeParameters) =>
              typeParameters.isNotEmpty,
            _ => false,
          },
    FunctionExpressionInvocation(:final typeArguments, :final element) =>
      typeArguments == null &&
          (element == null || element.typeParameters.isNotEmpty),
    _ => false,
  };

  bool _hasComment(
    VariableDeclarationStatement stmt,
    ReturnStatement returnStmt,
  ) {
    var token = stmt.beginToken;
    while (true) {
      if (token.precedingComments != null) return true;
      if (token == stmt.endToken) break;
      final next = token.next;
      if (next == null) break;
      token = next;
    }
    return returnStmt.returnKeyword.precedingComments != null;
  }

  bool _isReferencedElsewhere(
    Element target,
    NodeList<Statement> statements,
    int declIndex,
  ) {
    for (var k = 0; k < statements.length; k++) {
      if (k == declIndex || k == declIndex + 1) continue;
      final finder = _TargetFinder(target);
      statements[k].accept(finder);
      if (finder.found) return true;
    }
    return false;
  }
}

class _TargetFinder(final Element target) extends RecursiveAstVisitor<void> {
  bool found = false;

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (node.element == target) found = true;
  }
}
