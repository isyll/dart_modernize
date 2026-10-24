import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

import '../../engine/source_edit.dart';
import '../transformation.dart';

/// Collapses a call guarded by a null check into a null-aware call.
///
///     if (onChanged != null) onChanged!(value);   ->  onChanged?.call(value);
///     if (widget.onTap != null) {                 ->  widget.onTap?.call();
///       widget.onTap!();
///     }
///     if (controller != null) controller.dispose();  ->  controller?.dispose();
///
/// This is what the lint `prefer_null_aware_method_calls` asks for. Only an
/// `if` with no `else`, whose condition is `x != null` and whose body is one
/// call on exactly `x` (with or without `!`), possibly awaited. `x` is read
/// once where the `if` read it twice, so it must be stable: a local, a
/// parameter, a final field, or a final field read off one of those
/// (`widget.onTap`). The arguments may not mention `x`, which is no longer
/// promoted to non-null inside them. A comment anywhere in the statement
/// leaves it alone.
final class NullAwareCalls implements Transformation {
  const NullAwareCalls({required this.enabled});

  @override
  final bool enabled;

  @override
  String get name => 'null-aware-calls';

  @override
  Future<List<SourceEdit>> editsFor(ResolvedUnitResult unit) async {
    final visitor = _Visitor(unit.content);
    unit.unit.accept(visitor);
    return visitor.edits;
  }
}

class _Visitor(final String source) extends RecursiveAstVisitor<void> {
  final edits = <SourceEdit>[];

  @override
  void visitIfStatement(IfStatement node) {
    final replacement = _rewrite(node);
    if (replacement != null) {
      edits.add(
        .new(
          offset: node.offset,
          length: node.end - node.offset,
          replacement: replacement,
        ),
      );
      return;
    }
    super.visitIfStatement(node);
  }

  /// The single expression statement [statement] holds, directly or as the
  /// only statement of a block.
  ExpressionStatement? _onlyStatement(Statement statement) {
    if (statement is ExpressionStatement) return statement;
    if (statement is Block && statement.statements.length == 1) {
      final only = statement.statements.single;
      return only is ExpressionStatement ? only : null;
    }
    return null;
  }

  /// The replacement statement for [node], or null when it does not qualify.
  String? _rewrite(IfStatement node) {
    if (node.elseStatement != null || node.caseClause != null) return null;
    if (_hasComment(node)) return null;

    final subject = _nullChecked(node.expression);
    if (subject == null) return null;

    final statement = _onlyStatement(node.thenStatement);
    if (statement == null) return null;
    var call = statement.expression;
    final awaited = call is AwaitExpression;
    if (call is AwaitExpression) call = call.expression;

    final String rewritten;
    final ArgumentList arguments;
    if (call is MethodInvocation &&
        call.target != null &&
        !call.isNullAware &&
        !call.isCascaded) {
      // `x.m(args)` or `x!.m(args)` -> `x?.m(args)`.
      final target = _withoutBang(call.target!);
      if (!_sameReference(subject, target)) return null;
      arguments = call.argumentList;
      rewritten =
          '${_text(target)}?.${_text(call.methodName)}'
          '${call.typeArguments == null ? '' : _text(call.typeArguments!)}'
          '${_text(arguments)}';
    } else if (call is FunctionExpressionInvocation) {
      // `x!(args)` -> `x?.call(args)`.
      final function = _withoutBang(call.function);
      if (!_sameReference(subject, function)) return null;
      arguments = call.argumentList;
      rewritten =
          '${_text(function)}?.call'
          '${call.typeArguments == null ? '' : _text(call.typeArguments!)}'
          '${_text(arguments)}';
    } else if (call is MethodInvocation &&
        call.target == null &&
        call.methodName.element is VariableElement) {
      // `x(args)`, a promoted function-typed local -> `x?.call(args)`.
      if (!_sameReference(subject, call.methodName)) return null;
      arguments = call.argumentList;
      rewritten =
          '${_text(call.methodName)}?.call'
          '${call.typeArguments == null ? '' : _text(call.typeArguments!)}'
          '${_text(arguments)}';
    } else {
      return null;
    }

    final mentions = _Mentions(_elementOf(subject)!);
    arguments.accept(mentions);
    if (mentions.found) return null;

    return '${awaited ? 'await ' : ''}$rewritten;';
  }

  /// The element a stable reference resolves to: the local, parameter, or
  /// field getter at the end of it.
  Element? _elementOf(Expression expression) => switch (expression) {
    SimpleIdentifier(:final element) => element,
    PrefixedIdentifier(:final identifier) => identifier.element,
    PropertyAccess(:final propertyName) => propertyName.element,
    _ => null,
  };

  bool _hasComment(AstNode node) {
    for (var token = node.beginToken; ; token = token.next!) {
      if (token.precedingComments != null) return true;
      if (token == node.endToken) return false;
    }
  }

  /// Whether [element] reads the same value every time: a local, a parameter,
  /// or a final field.
  bool _isStable(Element? element) => switch (element) {
    LocalVariableElement() || FormalParameterElement() => true,
    GetterElement(:final variable) =>
      variable is FieldElement && variable.isFinal,
    FieldElement(:final isFinal) => isFinal,
    _ => false,
  };

  /// The expression [condition] compares to null with `!=`, when it is a
  /// stable reference.
  Expression? _nullChecked(Expression condition) {
    if (condition is! BinaryExpression || condition.operator.lexeme != '!=') {
      return null;
    }
    final Expression subject;
    if (condition.rightOperand is NullLiteral) {
      subject = condition.leftOperand;
    } else if (condition.leftOperand is NullLiteral) {
      subject = condition.rightOperand;
    } else {
      return null;
    }
    return _stableReference(subject) ? subject : null;
  }

  /// Whether [a] and [b] are the same stable reference, written the same way.
  bool _sameReference(Expression a, Expression b) =>
      _text(a) == _text(b) &&
      _elementOf(a) != null &&
      _elementOf(a) == _elementOf(b);

  /// Whether [expression] is `x`, `x.y` or `this.y` where every part is a
  /// local, a parameter, or a final field (the receiver of a field read may
  /// also be a getter, which is read once instead of twice).
  bool _stableReference(Expression expression) {
    if (expression is SimpleIdentifier) {
      return _isStable(expression.element) &&
          expression.staticType is! DynamicType;
    }
    if (expression is PrefixedIdentifier) {
      return expression.prefix.element is! PrefixElement &&
          _isStable(expression.identifier.element);
    }
    if (expression is PropertyAccess && !expression.isNullAware) {
      final target = expression.target;
      return (target is ThisExpression || target is SimpleIdentifier) &&
          _isStable(expression.propertyName.element);
    }
    return false;
  }

  String _text(AstNode node) => source.substring(node.offset, node.end);

  /// [expression] without a trailing `!`.
  Expression _withoutBang(Expression expression) =>
      expression is PostfixExpression && expression.operator.lexeme == '!'
      ? expression.operand
      : expression;
}

/// Looks for a use of [target] in the arguments, which lose the promotion.
class _Mentions(final Element target) extends RecursiveAstVisitor<void> {
  bool found = false;

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (node.element == target) found = true;
    super.visitSimpleIdentifier(node);
  }
}
