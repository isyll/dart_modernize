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
final class FinalLocals implements Transformation {
  @override
  final bool enabled;

  const FinalLocals({required this.enabled});

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
  final String source;
  final List<SourceEdit> edits = [];

  _FinalLocalsVisitor(this.source);

  @override
  void visitVariableDeclarationStatement(VariableDeclarationStatement node) {
    _collect(node);
    super.visitVariableDeclarationStatement(node);
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
      SourceEdit(
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
  final Object target;
  bool found = false;

  _ReassignmentFinder(this.target);

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
