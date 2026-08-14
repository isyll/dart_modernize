import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../../engine/source_edit.dart';
import '../transformation.dart';

/// Collapses a single-statement block body into a concise `=>` body for
/// functions, methods, getters, and closures.
///
/// A `{ return e; }` body becomes `=> e;`, and a void `{ e; }` body becomes
/// `=> e;`. The rewrite is purely syntactic: it never changes the value the
/// body produces, only how it is spelled.
///
/// Skipped when the arrow form would change meaning or lose something:
///
///   * more than one statement, an empty body, or a bare `return;`: there is
///     no single value for `=>` to carry;
///   * a comment anywhere inside the braces: the arrow form would drop it;
///   * setters, constructors, and `async`/`sync*` bodies: out of scope, or the
///     arrow form would be wrong;
///   * a returned expression that itself contains a closure: the inner closure
///     is collapsed instead, which keeps every edit non-overlapping and the
///     pass idempotent.
final class ExpressionBodies implements Transformation {
  const ExpressionBodies({required this.enabled});

  @override
  final bool enabled;

  @override
  String get name => 'expression-bodies';

  @override
  Future<List<SourceEdit>> editsFor(ResolvedUnitResult unit) async {
    final visitor = _ExpressionBodyVisitor(unit.content);
    unit.unit.accept(visitor);
    return visitor.edits;
  }
}

/// Detects whether a subtree contains a function expression (closure).
class _ClosureFinder extends RecursiveAstVisitor<void> {
  bool found = false;

  @override
  void visitFunctionExpression(FunctionExpression node) {
    found = true;
    // No need to descend further once a closure is seen.
  }
}

class _ExpressionBodyVisitor(final String source)
    extends RecursiveAstVisitor<void> {
  final edits = <SourceEdit>[];

  @override
  void visitBlockFunctionBody(BlockFunctionBody node) {
    _collect(node);
    // Keep descending so nested closures are considered on their own terms.
    super.visitBlockFunctionBody(node);
  }

  void _collect(BlockFunctionBody body) {
    // `async`, `async*`, and `sync*` bodies are out of scope: a generator
    // cannot be an arrow body at all, and async sugar is left for clarity.
    if (body.keyword != null) return;

    final bool needsSemicolon;
    final parent = body.parent;
    if (parent is MethodDeclaration) {
      if (parent.isSetter) return; // setters are intentionally left untouched
      needsSemicolon = true;
    } else if (parent is FunctionExpression) {
      // A named function declares its body (and so needs a trailing `;`); a
      // closure is part of a larger expression and must not gain one.
      needsSemicolon = parent.parent is FunctionDeclaration;
    } else {
      return; // constructors and anything else: skip
    }

    final block = body.block;
    if (block.statements.length != 1) return;

    final statement = block.statements.single;
    final Expression value;
    if (statement is ReturnStatement) {
      final expression = statement.expression;
      if (expression == null) return; // bare `return;` carries no value
      value = expression;
    } else if (statement is ExpressionStatement) {
      value = statement.expression;
    } else {
      return; // control flow, declarations, asserts, …
    }

    if (_hasInteriorComment(block)) return;
    if (_containsClosure(value)) return;

    final expressionSource = source.substring(value.offset, value.end);
    edits.add(
      .new(
        offset: block.offset,
        length: block.length,
        replacement: '=> $expressionSource${needsSemicolon ? ';' : ''}',
      ),
    );
  }

  bool _containsClosure(Expression expression) {
    final finder = _ClosureFinder();
    expression.accept(finder);
    return finder.found;
  }

  /// Whether any comment sits between the braces of [block].
  ///
  /// Scans from the token after `{` through `}` inclusive, so a leading comment
  /// on the statement and a trailing comment before `}` are both caught. A
  /// comment immediately before `{` is ignored: it lives outside the body and
  /// survives the rewrite untouched.
  bool _hasInteriorComment(Block block) {
    final last = block.rightBracket;
    for (
      var token = block.leftBracket.next;
      token != null;
      token = token.next
    ) {
      if (token.precedingComments != null) return true;
      if (token == last) break;
    }
    return false;
  }
}
