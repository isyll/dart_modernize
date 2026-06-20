import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../../engine/source_edit.dart';
import '../safe_reference.dart';
import '../transformation.dart';

/// Replaces null-guarded collection elements with the `?element` syntax.
///
/// Before: `[1, if (a != null) a]`
/// After:  `[1, ?a]`
///
/// Three guarded forms are recognised:
///   * `if (x != null) x`   – binary null check, bare value
///   * `if (x != null) x!`  – binary null check, forced non-null
///   * `if (x case var v?) v` – null-check pattern binding
///
/// The rewrite is only applied when the guarded expression is a side-effect-free
/// stable reference (a local variable or parameter), so collapsing from two
/// evaluations (test + use) to one preserves observable behaviour.
final class NullAwareElements implements Transformation {
  @override
  final bool enabled;

  const NullAwareElements({required this.enabled});

  @override
  String get name => 'null-aware-elements';

  @override
  Future<List<SourceEdit>> editsFor(ResolvedUnitResult unit) async {
    final visitor = _NullAwareElementsVisitor(unit.content);
    unit.unit.accept(visitor);
    return visitor.edits;
  }
}

class _NullAwareElementsVisitor extends RecursiveAstVisitor<void> {
  final String source;
  final List<SourceEdit> edits = [];

  _NullAwareElementsVisitor(this.source);

  @override
  void visitListLiteral(ListLiteral node) {
    super.visitListLiteral(node);
    _tryReplace(
      node.elements,
      node.leftBracket.offset,
      node.rightBracket.end,
      '[',
      ']',
    );
  }

  @override
  void visitSetOrMapLiteral(SetOrMapLiteral node) {
    super.visitSetOrMapLiteral(node);
    _tryReplace(
      node.elements,
      node.leftBracket.offset,
      node.rightBracket.end,
      '{',
      '}',
    );
  }

  String? _convert(CollectionElement elem) {
    if (elem is! IfElement) return null;
    if (elem.elseElement != null) return null;

    final caseClause = elem.caseClause;
    if (caseClause != null) return _convertCasePattern(elem, caseClause);

    return _convertBinaryNull(elem);
  }

  String? _convertBinaryNull(IfElement elem) {
    final condition = elem.expression;
    if (condition is! BinaryExpression) return null;
    if (condition.operator.lexeme != '!=') return null;
    if (condition.rightOperand is! NullLiteral) return null;

    final checkedExpr = condition.leftOperand;
    final guardElement = stableReference(checkedExpr);
    if (guardElement == null) return null;

    final then = elem.thenElement;
    if (then is! Expression) return null;

    Expression valueExpr = then;
    if (valueExpr is PostfixExpression && valueExpr.operator.lexeme == '!') {
      valueExpr = valueExpr.operand;
    }

    if (valueExpr is! SimpleIdentifier) return null;
    if (valueExpr.element != guardElement) return null;

    return '?${source.substring(checkedExpr.offset, checkedExpr.end)}';
  }

  String? _convertCasePattern(IfElement elem, CaseClause caseClause) {
    final pattern = caseClause.guardedPattern.pattern;
    if (pattern is! NullCheckPattern) return null;
    final inner = pattern.pattern;
    if (inner is! DeclaredVariablePattern) return null;

    final scrutinee = elem.expression;
    if (stableReference(scrutinee) == null) return null;

    final then = elem.thenElement;
    if (then is! SimpleIdentifier) return null;

    final boundElement = inner.declaredFragment?.element;
    if (boundElement == null) return null;
    if (then.element != boundElement) return null;

    return '?${source.substring(scrutinee.offset, scrutinee.end)}';
  }

  void _tryReplace(
    NodeList<CollectionElement> elements,
    int leftOffset,
    int rightEnd,
    String open,
    String close,
  ) {
    var hasConvertible = false;
    final parts = <String>[];

    for (final elem in elements) {
      final converted = _convert(elem);
      if (converted != null) {
        hasConvertible = true;
        parts.add(converted);
      } else {
        parts.add(source.substring(elem.offset, elem.end));
      }
    }

    if (!hasConvertible) return;

    edits.add(
      .new(
        offset: leftOffset,
        length: rightEnd - leftOffset,
        replacement: '$open${parts.join(', ')}$close',
      ),
    );
  }
}
