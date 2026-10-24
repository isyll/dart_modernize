import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

import '../../engine/source_edit.dart';
import '../transformation.dart';

/// Writes a wait as `Future.pause` (Dart 3.13).
///
///     await Future.delayed(const Duration(milliseconds: 300));
///         ->  await Future.pause(const Duration(milliseconds: 300));
///     await Future.delayed(Duration.zero);  ->  await Future.pause();
///
/// Only a `Future.delayed` with a single duration and no callback, whose
/// value nobody reads: awaited as a statement, used as a statement, or
/// returned from a function declared to return `Future<void>`.
/// `Future.delayed` without a callback completes with null typed as its type
/// argument, which `Future.pause`'s `Future<void>` would change, so an explicit
/// type argument other than `void` is left alone too. Skipped when the SDK has
/// no `Future.pause`.
final class FuturePause implements Transformation {
  const FuturePause({required this.enabled});

  @override
  final bool enabled;

  @override
  String get name => 'future-pause';

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
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    _collect(node);
    super.visitInstanceCreationExpression(node);
  }

  void _collect(InstanceCreationExpression node) {
    final constructor = node.constructorName.element;
    if (constructor == null || constructor.name != 'delayed') return;
    final future = constructor.enclosingElement;
    if (future is! ClassElement || !_isDartAsyncFuture(future)) return;
    final pause = future.getMethod('pause');
    if (pause == null || !pause.isStatic) return;

    final type = node.constructorName.type;
    final typeArguments = type.typeArguments?.arguments;
    if (typeArguments != null &&
        (typeArguments.length != 1 || typeArguments.single.type is! VoidType)) {
      return;
    }

    final arguments = node.argumentList.arguments;
    if (arguments.length != 1) return;
    final duration = arguments.single;
    if (duration is! Expression) return;
    if (!_valueIsUnused(node)) return;

    final prefix = type.importPrefix;
    final futureText = prefix == null
        ? 'Future'
        : '${prefix.name.lexeme}.Future';
    final argument = _isDurationZero(duration)
        ? ''
        : source.substring(duration.offset, duration.end);
    edits.add(
      .new(
        offset: node.offset,
        length: node.end - node.offset,
        replacement: '$futureText.pause($argument)',
      ),
    );
  }

  /// The declared return type of the function enclosing [node].
  DartType? _enclosingReturnType(AstNode node) {
    final body = node.thisOrAncestorOfType<FunctionBody>();
    final owner = body?.parent;
    return switch (owner) {
      MethodDeclaration() => owner.returnType?.type,
      FunctionExpression() => switch (owner.parent) {
        FunctionDeclaration(:final returnType) => returnType?.type,
        _ => null,
      },
      _ => null,
    };
  }

  bool _isDartAsyncFuture(ClassElement element) =>
      element.name == 'Future' &&
      element.library.uri.toString() == 'dart:async';

  /// Whether [expression] is `Duration.zero` from `dart:core`.
  bool _isDurationZero(Expression expression) {
    if (expression is! PrefixedIdentifier) return false;
    final element = expression.identifier.element;
    final owner = element?.enclosingElement;
    return expression.identifier.name == 'zero' &&
        owner is ClassElement &&
        owner.name == 'Duration' &&
        owner.library.uri.toString() == 'dart:core';
  }

  /// Whether the value of the `Future.delayed(...)` at [node] is never read:
  /// the expression of a statement (awaited or not), or the value returned
  /// from a function declared to return `Future<void>`.
  bool _valueIsUnused(Expression node) {
    AstNode current = node;
    var parent = current.parent;
    if (parent is AwaitExpression) {
      current = parent;
      parent = current.parent;
    }
    if (parent is ExpressionStatement) return true;
    if (parent is ReturnStatement || parent is ExpressionFunctionBody) {
      final returnType = _enclosingReturnType(parent!);
      return returnType is InterfaceType &&
          returnType.isDartAsyncFuture &&
          returnType.typeArguments.length == 1 &&
          returnType.typeArguments.single is VoidType;
    }
    return false;
  }
}
