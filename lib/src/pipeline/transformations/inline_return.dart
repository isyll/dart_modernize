import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';

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
///     return that would be lost by removing the declaration line.
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
