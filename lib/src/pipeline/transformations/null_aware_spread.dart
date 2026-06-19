import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';

import '../../engine/source_edit.dart';
import '../transformation.dart';

/// Replaces null-guarded spread elements with the `...?` null-aware spread.
///
/// Before: `[...base, if (extra != null) ...extra]`
/// After:  `[...base, ...?extra]`
///
/// The rewrite is only applied when the guarded expression is a side-effect-free
/// stable reference (a local variable or parameter), so collapsing from two
/// evaluations (test + use) to one preserves observable behaviour.
final class NullAwareSpread implements Transformation {
  @override
  final bool enabled;

  const NullAwareSpread({required this.enabled});

  @override
  String get name => 'null-aware-spread';

  @override
  Future<List<SourceEdit>> editsFor(ResolvedUnitResult unit) async {
    final visitor = _NullAwareSpreadVisitor(unit.content);
    unit.unit.accept(visitor);
    return visitor.edits;
  }
}

class _NullAwareSpreadVisitor extends RecursiveAstVisitor<void> {
  final String source;
  final List<SourceEdit> edits = [];

  _NullAwareSpreadVisitor(this.source);

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

  String? _convert(CollectionElement elem) {
    if (elem is! IfElement) return null;
    if (elem.elseElement != null) return null;

    final condition = elem.expression;
    if (condition is! BinaryExpression) return null;
    if (condition.operator.lexeme != '!=') return null;
    if (condition.rightOperand is! NullLiteral) return null;

    final checkedExpr = condition.leftOperand;
    final guardElement = _safeRef(checkedExpr);
    if (guardElement == null) return null;

    final then = elem.thenElement;
    if (then is! SpreadElement) return null;

    final spreadExpr = then.expression;
    if (spreadExpr is! SimpleIdentifier) return null;
    if (spreadExpr.element != guardElement) return null;

    return '...?${source.substring(checkedExpr.offset, checkedExpr.end)}';
  }
}

/// Returns the resolved element if [expr] is a side-effect-free stable
/// reference (a local variable or parameter), otherwise `null`.
Element? _safeRef(Expression expr) {
  if (expr is! SimpleIdentifier) return null;
  final element = expr.element;
  if (element is LocalVariableElement || element is FormalParameterElement) {
    return element;
  }
  return null;
}
