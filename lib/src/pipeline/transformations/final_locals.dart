import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../../engine/source_edit.dart';
import '../transformation.dart';

/// Replaces `var` with `final` on locals that are never written to.
///
///     var result = compute();    ->  final result = compute();
///     for (var x in xs)          ->  for (final x in xs)
///
/// The scan covers the whole enclosing function, so a write from inside a
/// closure counts.
///
/// Skipped when:
///   * the keyword is not exactly `var`;
///   * a variable has no initializer;
///   * a variable is assigned, compound-assigned, or incremented anywhere;
///   * one variable in a multi-variable declaration fails: the whole
///     declaration is left alone.
///
/// A classic `for (var i = 0; ...; i++)` and pattern declarations
/// (`var (x, y) = ...`) are different AST nodes and are never touched.
///
/// The lint `prefer_final_in_for_each` covers the for-in half, but it is not in
/// `package:lints/recommended.yaml`, so `dart fix` only applies it where a
/// project opts in. This pass does it everywhere. They cannot collide: this
/// runs in the transform stage, fix-all runs later on the finished file.
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
