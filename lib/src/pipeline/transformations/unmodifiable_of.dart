import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

import '../../engine/source_edit.dart';
import '../transformation.dart';

/// Writes `List.unmodifiable(x)` as `List.unmodifiableOf(x)`, and the same for
/// `Map` (Dart 3.13). Off by default.
///
/// The old constructors take an untyped `Iterable` or `Map`, so their type
/// arguments come from the context alone (`List<dynamic>` with none), where
/// the new ones also infer them from the argument. The rewrite is made only
/// when the argument's type arguments are exactly the ones the call already
/// has, so the result keeps its static type and the argument still fits, and
/// when the argument's own type does not come from its context (a variable, a
/// typed literal like `<int>[1, 2]`, a call that is not generic). Skipped when
/// the SDK has no `unmodifiableOf`.
final class UnmodifiableOf implements Transformation {
  const UnmodifiableOf({required this.enabled});

  @override
  final bool enabled;

  @override
  String get name => 'unmodifiable-of';

  @override
  Future<List<SourceEdit>> editsFor(ResolvedUnitResult unit) async {
    final visitor = _Visitor();
    unit.unit.accept(visitor);
    return visitor.edits;
  }
}

class _Visitor extends RecursiveAstVisitor<void> {
  final edits = <SourceEdit>[];

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    _collect(node);
    super.visitInstanceCreationExpression(node);
  }

  void _collect(InstanceCreationExpression node) {
    final name = node.constructorName.name;
    final constructor = node.constructorName.element;
    if (name == null || constructor == null || name.name != 'unmodifiable') {
      return;
    }
    final owner = constructor.enclosingElement;
    if (owner is! ClassElement ||
        owner.library.uri.toString() != 'dart:core' ||
        (owner.name != 'List' && owner.name != 'Map')) {
      return;
    }
    if (owner.getNamedConstructor('unmodifiableOf') == null) return;

    final arguments = node.argumentList.arguments;
    if (arguments.length != 1) return;
    final value = arguments.single;
    if (value is! Expression || !_typeIgnoresContext(value)) return;
    final result = node.staticType;
    final argument = value.staticType;
    if (result is! InterfaceType || argument is! InterfaceType) return;

    final expected = owner.name == 'List'
        ? argument.asInstanceOf(
            result.element.library.typeProvider.iterableElement,
          )
        : argument.asInstanceOf(owner);
    if (expected == null) return;
    if (!_sameArguments(result.typeArguments, expected.typeArguments)) return;

    edits.add(
      .new(
        offset: name.offset,
        length: name.length,
        replacement: 'unmodifiableOf',
      ),
    );
  }

  /// Whether [expression] has the same static type in any context.
  bool _typeIgnoresContext(Expression expression) => switch (expression) {
    SimpleIdentifier() || PrefixedIdentifier() || AsExpression() => true,
    PropertyAccess(:final isNullAware) => !isNullAware,
    TypedLiteral(:final typeArguments) => typeArguments != null,
    ParenthesizedExpression(:final expression) => _typeIgnoresContext(
      expression,
    ),
    InstanceCreationExpression(:final constructorName) =>
      constructorName.type.typeArguments != null ||
          (constructorName.element?.enclosingElement.typeParameters.isEmpty ??
              false),
    MethodInvocation(:final typeArguments, :final methodName) =>
      typeArguments != null ||
          switch (methodName.element) {
            ExecutableElement(:final typeParameters) => typeParameters.isEmpty,
            _ => false,
          },
    _ => false,
  };

  bool _sameArguments(List<DartType> a, List<DartType> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
