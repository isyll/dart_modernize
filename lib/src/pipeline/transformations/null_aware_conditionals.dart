import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type_system.dart';

import '../../engine/edit_collector.dart';
import '../../engine/source_edit.dart';
import '../safe_reference.dart';
import '../transformation.dart';

/// Turns a null check written with `? :` into a null-aware operator.
///
///     x == null ? null : x[0]        ->  x?[0]
///     x != null ? x.name : fallback  ->  x?.name ?? fallback
///
/// Only these two shapes. `dart fix` already covers the others, because the
/// lints prefer_if_null_operators and prefer_null_aware_operators ship in
/// package:lints/recommended.yaml, and the fix-all pass runs `dart fix`.
///
/// Skipped when:
///   * `x` is not a plain local or parameter. The rewrite reads it once where
///     the conditional read it twice, so it has to be a stable value.
///   * the branch is a bare `x`, or a property read against `null`. Those are
///     the lints' cases, not ours.
///   * the fallback form would change the result. `x != null ? x.foo : d`
///     gives null when `x.foo` is null, while `x?.foo ?? d` gives `d`. So the
///     chain's type has to be non-nullable.
///
/// No parentheses are needed around the result: `??` binds tighter than `? :`,
/// and `?[]` is a selector.
final class NullAwareConditionals implements Transformation {
  const NullAwareConditionals({required this.enabled});

  @override
  final bool enabled;

  @override
  String get name => 'null-aware-conditionals';

  @override
  Future<List<SourceEdit>> editsFor(ResolvedUnitResult unit) async {
    final visitor = _NullAwareConditionalsVisitor(
      unit.content,
      unit.libraryElement.typeSystem,
    );
    unit.unit.accept(visitor);
    return visitor.edits;
  }
}

class _NullAwareConditionalsVisitor(
  final String source,
  final TypeSystem typeSystem,
) extends RecursiveAstVisitor<void> {
  final edits = <SourceEdit>[];

  @override
  void visitConditionalExpression(ConditionalExpression node) {
    final replacement = _rewrite(node);
    if (replacement == null) {
      // Not rewritable itself, but it may contain something that is.
      super.visitConditionalExpression(node);
      return;
    }
    edits.add(
      .new(
        offset: node.offset,
        length: node.end - node.offset,
        replacement: replacement,
      ),
    );
    // No `super` call: _render already handled anything nested. Recursing too
    // would add edits inside the span we just replaced, and EditCollector drops
    // overlapping edits.
  }

  /// Returns the replacement text for [node], or null when it does not qualify.
  String? _rewrite(ConditionalExpression node) {
    final test = _NullTest.from(node.condition);
    if (test == null) return null;

    // Order the branches by what the test proved, so `== null` and `!= null`
    // share one code path.
    final (nonNullBranch, nullBranch) = test.isEqualsNull
        ? (node.elseExpression, node.thenExpression)
        : (node.thenExpression, node.elseExpression);

    final chain = _SelectorChain.from(nonNullBranch, test.element);
    if (chain == null) return null;

    // A `?` right after the root reference turns `x.name` into `x?.name` and
    // `x[0]` into `x?[0]`.
    final rewritten = _render(chain.expression, insertAt: chain.rootEnd);

    if (nullBranch is NullLiteral) {
      // prefer_null_aware_operators handles property and method chains here.
      if (!chain.isIndexed) return null;
      return rewritten;
    }

    final type = chain.expression.staticType;
    if (type == null || !typeSystem.isNonNullable(type)) return null;

    return '$rewritten ?? ${_render(nullBranch)}';
  }

  /// The source of [expression], with any nested rewrite already applied and a
  /// `?` inserted at [insertAt].
  ///
  /// Reusing the original text keeps comments and line breaks intact. Running
  /// the pass on the sub-expression handles a fallback that is itself a null
  /// check, so `a != null ? a.name : (b != null ? b.name : '')` is done in one
  /// go instead of needing a second run.
  String _render(Expression expression, {int? insertAt}) {
    final start = expression.offset;

    final nested = _NullAwareConditionalsVisitor(source, typeSystem);
    expression.accept(nested);

    final collector = EditCollector();
    for (final edit in nested.edits) {
      collector.add(
        .new(
          offset: edit.offset - start,
          length: edit.length,
          replacement: edit.replacement,
        ),
      );
    }
    if (insertAt != null) {
      collector.add(
        .new(offset: insertAt - start, length: 0, replacement: '?'),
      );
    }

    return collector.apply(source.substring(start, expression.end));
  }
}

/// An `x == null` or `x != null` test on a local or parameter.
final class _NullTest {
  const _NullTest({required this.element, required this.isEqualsNull});

  /// The test [condition] describes, or null if it is not one.
  static _NullTest? from(Expression condition) {
    if (condition is! BinaryExpression) return null;
    final operator = condition.operator.lexeme;
    if (operator != '==' && operator != '!=') return null;

    // Accept the null literal on either side: `x == null` and `null == x`.
    final Expression operand;
    if (condition.rightOperand is NullLiteral) {
      operand = condition.leftOperand;
    } else if (condition.leftOperand is NullLiteral) {
      operand = condition.rightOperand;
    } else {
      return null;
    }

    final element = stableReference(operand);
    if (element == null) return null;
    return .new(element: element, isEqualsNull: operator == '==');
  }

  /// The local or parameter the test reads.
  final Element element;

  /// True for `== null`, false for `!= null`.
  final bool isEqualsNull;
}

/// A selector chain (`x.a`, `x.m()`, `x[0]`, and combinations) rooted at a
/// known element.
final class _SelectorChain {
  const _SelectorChain({
    required this.expression,
    required this.rootEnd,
    required this.isIndexed,
  });

  /// True when [expression] is a plain read, not a cascade and not already
  /// null-aware.
  static bool _isPlainRead(Expression expression) {
    if (expression is IndexExpression) {
      return !expression.isCascaded && !expression.isNullAware;
    }
    if (expression is MethodInvocation) {
      return !expression.isCascaded && !expression.isNullAware;
    }
    if (expression is PropertyAccess) {
      return !expression.isCascaded && !expression.isNullAware;
    }
    return false;
  }

  /// The chain [expression] forms over [root], or null if it is rooted
  /// elsewhere or is just the bare reference.
  ///
  /// Walks down the receivers so a longer chain like `x.items.length` is
  /// handled as one edit.
  static _SelectorChain? from(Expression expression, Element root) {
    final isIndexed = expression is IndexExpression;

    var current = expression;
    var depth = 0;
    while (true) {
      // Cascades and reads that are already null-aware are left alone.
      Expression? next;
      if (current is IndexExpression && _isPlainRead(current)) {
        next = current.target;
      } else if (current is MethodInvocation && _isPlainRead(current)) {
        next = current.target;
      } else if (current is PropertyAccess && _isPlainRead(current)) {
        next = current.target;
      } else if (current is PrefixedIdentifier) {
        next = current.prefix;
      }
      if (next == null) break;
      current = next;
      depth++;
    }

    // The root has to be the reference the null test checked.
    if (current is! SimpleIdentifier || current.element != root) return null;
    // A bare `x` is `x ?? d`, which prefer_if_null_operators handles.
    if (depth == 0) return null;

    return .new(
      expression: expression,
      rootEnd: current.end,
      isIndexed: isIndexed,
    );
  }

  /// The full chain expression, e.g. `x.items.length`.
  final Expression expression;

  /// Source offset just past the root reference, where the `?` is spliced in.
  final int rootEnd;

  /// True when the outermost selector is an index read, the form no lint fixes.
  final bool isIndexed;
}
