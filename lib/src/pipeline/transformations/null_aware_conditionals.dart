import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type_system.dart';

import '../../engine/edit_collector.dart';
import '../../engine/source_edit.dart';
import '../safe_reference.dart';
import '../transformation.dart';

/// Collapses null-check conditionals into null-aware operators, for the two
/// shapes `dart fix` leaves behind.
///
/// Before: `x == null ? null : x[0]`      After: `x?[0]`
/// Before: `x != null ? x.name : fallback` After: `x?.name ?? fallback`
///
/// **Scope is deliberately narrow.** The lints `prefer_if_null_operators` and
/// `prefer_null_aware_operators` are both in `package:lints/recommended.yaml`,
/// so for most projects `dart fix` (the fix-all pass) already rewrites
/// `x == null ? d : x` to `x ?? d` and `x == null ? null : x.foo` to `x?.foo`,
/// in either operand order and through deep chains. Redoing that here would
/// duplicate fix-all, so this pass handles only what those lints miss:
///
///   * **null-aware index**: `x == null ? null : x[i]` becomes `x?[i]`. No lint
///     flags the index form, in either operand order.
///   * **null-aware chain with a fallback**: `x != null ? x.name : d` becomes
///     `x?.name ?? d`. The lints handle a `null` alternative but not an
///     arbitrary one, because that needs the type check below.
///
/// The rewrite is applied only when ALL of the following hold:
///   * the tested expression is a side-effect-free stable reference (a local or
///     a parameter), so folding two reads into one preserves behavior;
///   * the non-null branch is a selector chain rooted at that same element, and
///     is strictly deeper than the bare reference (a bare `x` is the plain
///     if-null case the lint already owns);
///   * for the fallback form, the chain's static type is non-nullable. This is
///     the load-bearing guard: with a nullable chain, `x != null ? x.foo : d`
///     yields `null` when `x.foo` is null, while `x?.foo ?? d` yields `d`, so
///     the rewrite would change behavior.
///
/// Precedence is safe without parentheses: `??` binds tighter than `? :`, and
/// `?[]` is a selector, so either replacement fits wherever the conditional did.
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

class _NullAwareConditionalsVisitor extends RecursiveAstVisitor<void> {
  _NullAwareConditionalsVisitor(this.source, this.typeSystem);
  final String source;
  final TypeSystem typeSystem;

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
    // Deliberately no `super` call: [_render] already folded every nested
    // rewrite into `replacement`. Descending as well would queue edits inside a
    // span this one replaces, and EditCollector drops overlaps, so the nested
    // rewrite would silently reappear as pending work on the next run.
  }

  /// Returns the replacement text for [node], or null when it does not qualify.
  String? _rewrite(ConditionalExpression node) {
    final test = _NullTest.from(node.condition);
    if (test == null) return null;

    // Line the branches up by what the test proved, not by their syntactic
    // position, so both operand orders funnel into one code path.
    final (nonNullBranch, nullBranch) = test.isEqualsNull
        ? (node.elseExpression, node.thenExpression)
        : (node.thenExpression, node.elseExpression);

    final chain = _SelectorChain.from(nonNullBranch, test.element);
    if (chain == null) return null;

    // A `?` right after the root reference turns `x.name` into `x?.name` and
    // `x[0]` into `x?[0]`.
    final rewritten = _render(chain.expression, insertAt: chain.rootEnd);

    if (nullBranch is NullLiteral) {
      // Property and method chains against a `null` alternative are exactly
      // what prefer_null_aware_operators fixes; only the index form is ours.
      if (!chain.isIndexed) return null;
      return rewritten;
    }

    final type = chain.expression.staticType;
    if (type == null || !typeSystem.isNonNullable(type)) return null;

    return '$rewritten ?? ${_render(nullBranch)}';
  }

  /// Renders [expression]'s source with this pass's own nested rewrites already
  /// applied, optionally splicing a `?` in at [insertAt].
  ///
  /// Working from the original text rather than reprinting the AST keeps
  /// comments and line breaks inside the expression byte-for-byte intact. The
  /// nested run is what makes a single pipeline run converge: a fallback that is
  /// itself a null-check conditional, as in `a != null ? a.name : (b != null ?
  /// b.name : '')`, is folded here instead of being left for a second run.
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

/// A `x == null` / `x != null` test against a stable reference.
final class _NullTest {
  const _NullTest({required this.element, required this.isEqualsNull});

  /// Returns the test described by [condition], or null when it is not a null
  /// check against a side-effect-free reference.
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

  /// Returns the chain [expression] forms over [root], or null when it is not
  /// one, is rooted elsewhere, or is just the bare reference.
  ///
  /// Walking down the receivers keeps the whole chain in one edit, so
  /// `x.items.length` becomes `x?.items.length` rather than being rejected for
  /// having more than one selector.
  static _SelectorChain? from(Expression expression, Element root) {
    final isIndexed = expression is IndexExpression;

    var current = expression;
    var depth = 0;
    while (true) {
      final Expression? next = switch (current) {
        // A cascade has its own receiver semantics, and a null-aware root is
        // already what this pass would produce, so neither is rewritten.
        IndexExpression(isCascaded: false, isNullAware: false, :final target) =>
          target,
        MethodInvocation(
          isCascaded: false,
          isNullAware: false,
          :final target,
        ) =>
          target,
        PropertyAccess(isCascaded: false, isNullAware: false, :final target) =>
          target,
        PrefixedIdentifier(:final prefix) => prefix,
        _ => null,
      };
      if (next == null) break;
      current = next;
      depth++;
    }

    // The root must be the very reference the null test proved non-null.
    if (current is! SimpleIdentifier || current.element != root) return null;
    // A bare `x` is `x ?? d`, which prefer_if_null_operators already fixes.
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
