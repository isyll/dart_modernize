import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';

import '../../engine/source_edit.dart';
import '../transformation.dart';

/// Collapses a freshly declared local followed by a contiguous run of member
/// writes and method calls on that same target into a single cascade chain.
///
/// Before:
///   var p = Paint();
///   p.color = c;
///   p.strokeWidth = 5.0;
///
/// After:
///   var p = Paint()
///     ..color = c
///     ..strokeWidth = 5.0;
///
/// The rewrite is applied only when ALL of the following hold:
///   * the target is a single local declaration with an initializer;
///   * the run is contiguous (no unrelated statements interleaved);
///   * the run contains at least two operations;
///   * no right-hand side in the run references the target variable (which
///     would be unbound during cascade evaluation).
final class Cascades implements Transformation {
  @override
  final bool enabled;

  const Cascades({required this.enabled});

  @override
  String get name => 'cascades';

  @override
  Future<List<SourceEdit>> editsFor(ResolvedUnitResult unit) async {
    final visitor = _CascadeVisitor(unit.content);
    unit.unit.accept(visitor);
    return visitor.edits;
  }
}

class _CascadeVisitor extends RecursiveAstVisitor<void> {
  final String source;
  final List<SourceEdit> edits = [];

  _CascadeVisitor(this.source);

  @override
  void visitBlock(Block node) {
    _collectCascades(node.statements);
    super.visitBlock(node);
  }

  /// Extracts the member portion of a cascade item (after the `..` operator).
  ///
  /// For `p.color = c` returns `color = c`.
  /// For `p.add('x')` returns `add('x')`.
  String _cascadeItem(ExpressionStatement stmt) {
    final expr = stmt.expression;

    if (expr is AssignmentExpression) {
      final lhs = expr.leftHandSide;
      if (lhs is PrefixedIdentifier) {
        return source.substring(lhs.identifier.offset, expr.end);
      }
      if (lhs is PropertyAccess) {
        return source.substring(lhs.propertyName.offset, expr.end);
      }
    }

    if (expr is MethodInvocation) {
      return source.substring(expr.methodName.offset, expr.end);
    }

    throw StateError('Unexpected cascade item expression: $expr');
  }

  void _collectCascades(NodeList<Statement> statements) {
    for (var i = 0; i < statements.length; i++) {
      final stmt = statements[i];
      if (stmt is! VariableDeclarationStatement) continue;

      final variables = stmt.variables;
      if (variables.variables.length != 1) continue;

      final varDecl = variables.variables.single;
      if (varDecl.initializer == null) continue;

      final element = varDecl.declaredFragment?.element;
      if (element == null) continue;

      final run = <ExpressionStatement>[];
      for (var j = i + 1; j < statements.length; j++) {
        final next = statements[j];
        if (next is! ExpressionStatement) break;
        if (!_isMemberWriteOrCallOn(element, next)) break;
        if (_rhsReferencesTarget(element, next)) break;
        run.add(next);
      }

      if (run.length < 2) continue;

      final indent = _leadingIndent(stmt.offset);
      final cascadeIndent = '$indent  ';
      final items = run
          .map((s) => '\n$cascadeIndent..${_cascadeItem(s)}')
          .join('');

      if (_isUnusedAfterRun(element, statements, i, run.length)) {
        final receiverText = source.substring(
          varDecl.initializer!.offset,
          varDecl.initializer!.end,
        );
        edits.add(
          .new(
            offset: stmt.offset,
            length: run.last.end - stmt.offset,
            replacement: '$receiverText$items;',
          ),
        );
      } else {
        edits.add(
          .new(
            offset: stmt.semicolon.offset,
            length: run.last.end - stmt.semicolon.offset,
            replacement: '$items;',
          ),
        );
      }
    }
  }

  bool _isMemberWriteOrCallOn(Element target, ExpressionStatement stmt) {
    final expr = stmt.expression;

    if (expr is AssignmentExpression) {
      return _isTargetMemberAccess(target, expr.leftHandSide);
    }

    if (expr is MethodInvocation) {
      final t = expr.target;
      if (t == null) return false;
      if (expr.operator?.lexeme != '.') return false;
      return _isTargetRef(target, t);
    }

    return false;
  }

  bool _isTargetMemberAccess(Element target, Expression lhs) {
    if (lhs is PrefixedIdentifier) {
      return _isTargetRef(target, lhs.prefix);
    }
    if (lhs is PropertyAccess) {
      if (lhs.operator.lexeme != '.') return false;
      return _isTargetRef(target, lhs.target);
    }
    return false;
  }

  bool _isTargetRef(Element target, Expression? expr) {
    if (expr == null) return false;
    if (expr is SimpleIdentifier) return expr.element == target;
    return false;
  }

  bool _isUnusedAfterRun(
    Element target,
    NodeList<Statement> statements,
    int declIndex,
    int runLength,
  ) {
    for (var k = declIndex + runLength + 1; k < statements.length; k++) {
      final finder = _TargetFinder(target);
      statements[k].accept(finder);
      if (finder.found) return false;
    }
    return true;
  }

  String _leadingIndent(int offset) {
    var pos = offset - 1;
    while (pos >= 0 && source[pos] != '\n') {
      pos--;
    }
    final lineStart = pos + 1;
    final buf = StringBuffer();
    for (var i = lineStart; i < offset; i++) {
      final ch = source[i];
      if (ch == ' ' || ch == '\t') {
        buf.write(ch);
      } else {
        break;
      }
    }
    return buf.toString();
  }

  bool _rhsReferencesTarget(Element target, ExpressionStatement stmt) {
    final expr = stmt.expression;
    if (expr is AssignmentExpression) {
      return _subtreeContainsTarget(target, expr.rightHandSide);
    }
    if (expr is MethodInvocation) {
      return _subtreeContainsTarget(target, expr.argumentList);
    }
    return false;
  }

  bool _subtreeContainsTarget(Element target, AstNode node) {
    final finder = _TargetFinder(target);
    node.accept(finder);
    return finder.found;
  }
}

class _TargetFinder extends RecursiveAstVisitor<void> {
  final Element target;
  bool found = false;

  _TargetFinder(this.target);

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (node.element == target) found = true;
  }
}
