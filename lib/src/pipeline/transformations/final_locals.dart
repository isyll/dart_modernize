import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../../engine/source_edit.dart';
import '../transformation.dart';

/// Replaces `var` with `final` on local variable declarations whose variables
/// are never reassigned, incremented, or decremented anywhere in the enclosing
/// function body (including inside nested closures).
///
/// Before:
///   var result = compute();   // result never reassigned
///
/// After:
///   final result = compute();
///
/// The rewrite is applied only when ALL of the following hold:
///   * the declaration keyword is exactly `var` (not `final`, `const`, `late`);
///   * every variable in the declaration list has an initializer;
///   * none of the variables is reassigned, compound-assigned, or incremented/
///     decremented anywhere reachable from the enclosing function body;
///   * for a multi-variable list (`var a = .., b = ..;`), all variables must
///     qualify; if any is reassigned the whole declaration is left unchanged.
///
/// Pattern declarations (`var (x, y) = ...`) are a different AST node and
/// are never visited.
///
/// The same `var` -> `final` rule is applied to for-in loop variables, so
/// `for (var x in xs)` becomes `for (final x in xs)` when `x` is never
/// reassigned in the loop. A classic `for (var i = 0; ...; i++)` is a different
/// AST node and is left alone; its counter is mutated by definition.
///
/// The lint `prefer_final_in_for_each` covers the for-in case, so `dart fix`
/// applies it too, but only for projects that enable that rule (it is not in
/// `package:lints/recommended.yaml`). This pass does it for every project. The
/// two cannot collide: this pass runs in the transform stage and fix-all runs
/// later over the finalized file, where the loop already reads `final`.
final class FinalLocals implements Transformation {
  const FinalLocals({required this.enabled});

  @override
  final bool enabled;

  @override
  String get name => 'final-locals';

  @override
  Future<List<SourceEdit>> editsFor(ResolvedUnitResult unit) async {
    final visitor = _FinalLocalsVisitor(unit.content);
    unit.unit.accept(visitor);
    return visitor.edits;
  }
}

class _FinalLocalsVisitor extends RecursiveAstVisitor<void> {
  _FinalLocalsVisitor(this.source);
  final String source;

  final edits = <SourceEdit>[];

  @override
  void visitVariableDeclarationStatement(VariableDeclarationStatement node) {
    _collect(node);
    super.visitVariableDeclarationStatement(node);
  }

  @override
  void visitForEachPartsWithDeclaration(ForEachPartsWithDeclaration node) {
    _collectLoopVariable(node);
    super.visitForEachPartsWithDeclaration(node);
  }

  /// Upgrades `for (var x in xs)` to `for (final x in xs)`.
  ///
  /// The reassignment scan covers the whole enclosing for statement, which is
  /// the loop variable's entire scope, so a closure in the body that writes to
  /// it is still seen. Matching is by element identity, so a same-named
  /// variable elsewhere never counts.
  void _collectLoopVariable(ForEachPartsWithDeclaration node) {
    final loopVariable = node.loopVariable;
    final keyword = loopVariable.keyword;
    if (keyword?.lexeme != 'var') return;

    final element = loopVariable.declaredFragment?.element;
    if (element == null) return;

    // The parent is the enclosing `for` statement (or collection `for` element),
    // which is exactly the loop variable's scope.
    final finder = _ReassignmentFinder(element);
    node.parent.accept(finder);
    if (finder.found) return;

    edits.add(
      .new(
        offset: keyword!.offset,
        length: keyword.length,
        replacement: 'final',
      ),
    );
  }

  void _collect(VariableDeclarationStatement stmt) {
    final vars = stmt.variables;

    if (vars.keyword?.lexeme != 'var') return;

    final varDecls = vars.variables;
    if (varDecls.any((v) => v.initializer == null)) return;

    final body = _enclosingFunctionBody(stmt);
    if (body == null) return;

    for (final varDecl in varDecls) {
      final element = varDecl.declaredFragment?.element;
      if (element == null) return;
      final finder = _ReassignmentFinder(element);
      body.accept(finder);
      if (finder.found) return;
    }

    final varToken = vars.keyword!;
    edits.add(
      .new(
        offset: varToken.offset,
        length: varToken.length,
        replacement: 'final',
      ),
    );
  }

  AstNode? _enclosingFunctionBody(AstNode node) {
    for (var n = node.parent; n != null; n = n.parent) {
      if (n is FunctionBody) return n;
    }
    return null;
  }
}

class _ReassignmentFinder extends RecursiveAstVisitor<void> {
  _ReassignmentFinder(this.target);
  final Object target;

  bool found = false;

  @override
  void visitAssignmentExpression(AssignmentExpression node) {
    if (_isRef(node.leftHandSide)) found = true;
    super.visitAssignmentExpression(node);
  }

  @override
  void visitPostfixExpression(PostfixExpression node) {
    final op = node.operator.lexeme;
    if ((op == '++' || op == '--') && _isRef(node.operand)) found = true;
    super.visitPostfixExpression(node);
  }

  @override
  void visitPrefixExpression(PrefixExpression node) {
    final op = node.operator.lexeme;
    if ((op == '++' || op == '--') && _isRef(node.operand)) found = true;
    super.visitPrefixExpression(node);
  }

  bool _isRef(Expression expr) =>
      expr is SimpleIdentifier && expr.element == target;
}
