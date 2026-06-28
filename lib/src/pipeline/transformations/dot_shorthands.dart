import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

import '../../engine/source_edit.dart';
import '../transformation.dart';

/// Collapses `TypeName.member`, `TypeName(...)`, and `TypeName.named(...)` to
/// the Dart 3.10+ dot-shorthand form when the surrounding context type makes
/// the target unambiguous:
///
///   * `final Color c = Color.blue;`      → `final Color c = .blue;`
///   * `Handler h = Handler.empty();`     → `Handler h = .empty();`
///   * `Foo f = Foo();`                   → `Foo f = .new();`
///   * `Foo f = Foo.named();`             → `Foo f = .named();`
///
/// A shorthand is emitted only when the context type at the position resolves
/// to exactly the same type whose member/constructor is referenced, so that
/// `.member` resolves to the identical element and the static type is
/// unchanged. The context type is derived position by position (typed variable
/// or field, plain assignment target, return type, argument slot, collection
/// element, equality right-hand side, switch case, switch pattern). Wherever the
/// context type cannot be derived precisely, with `var`, `dynamic`, `Object`, an
/// inferred type variable, a supertype, or the left of `==`, the code is left
/// untouched.
final class DotShorthands implements Transformation {
  @override
  final bool enabled;

  const DotShorthands({required this.enabled});

  @override
  String get name => 'dot-shorthands';

  @override
  Future<List<SourceEdit>> editsFor(ResolvedUnitResult unit) async {
    final visitor = _DotShorthandsVisitor();
    unit.unit.accept(visitor);
    return visitor.edits;
  }
}

class _DotShorthandsVisitor extends RecursiveAstVisitor<void> {
  final List<SourceEdit> edits = [];

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final context = _contextType(node);
    if (context != null) {
      final edit = _constructorEdit(node, context);
      if (edit != null) edits.add(edit);
    }
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitListLiteral(ListLiteral node) {
    _annotateInferredList(node);
    super.visitListLiteral(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final context = _contextType(node);
    if (context != null) {
      final edit = _staticMethodEdit(node, context);
      if (edit != null) edits.add(edit);
    }
    super.visitMethodInvocation(node);
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    final context = _contextType(node);
    if (context != null) {
      final edit = _staticMemberEdit(node, context);
      if (edit != null) edits.add(edit);
    }
    super.visitPrefixedIdentifier(node);
  }

  /// When a list literal has no element type to fall back on (no explicit
  /// `<T>` and no downward context), collapsing its elements to shorthands
  /// would leave the compiler nothing to resolve against. If any element would
  /// collapse, make the inferred element type explicit (`<T>[...]`) so the
  /// shorthands stay valid.
  void _annotateInferredList(ListLiteral node) {
    if (node.typeArguments != null) return;

    final downward = _contextType(node);
    if (downward is InterfaceType &&
        (downward.isDartCoreList || downward.isDartCoreSet)) {
      return;
    }

    final inferred = node.staticType;
    if (inferred is! InterfaceType || inferred.typeArguments.length != 1) {
      return;
    }
    final elementType = inferred.typeArguments.first;

    if (!_anyElementCollapses(node.elements, elementType)) return;

    edits.add(
      .new(
        offset: node.leftBracket.offset,
        length: 0,
        replacement: '<${elementType.getDisplayString()}>',
      ),
    );
  }

  /// Whether any element in [elements] (recursing into ForElement/IfElement
  /// bodies) would collapse to a shorthand given [elementType] as context.
  bool _anyElementCollapses(
    Iterable<CollectionElement> elements,
    DartType elementType,
  ) {
    for (final e in elements) {
      if (e is Expression && _wouldCollapse(e, elementType)) return true;
      if (e is ForElement && _anyElementCollapses([e.body], elementType)) {
        return true;
      }
      if (e is IfElement) {
        if (_anyElementCollapses([e.thenElement], elementType)) return true;
        final elseEl = e.elseElement;
        if (elseEl != null && _anyElementCollapses([elseEl], elementType)) {
          return true;
        }
      }
    }
    return false;
  }

  /// Context type for an argument from the parameter slot it binds to.
  DartType? _argumentContext(Argument argument) {
    final parameter = argument.correspondingParameter;
    if (parameter == null) return null;

    final declared = parameter.baseElement.type;
    if (declared is TypeParameterType) {
      // A type variable of the invoked generic itself is solved *from* the
      // arguments, so it offers no downward context. A type variable of the
      // enclosing class is already fixed by the receiver, so keep going.
      final typeParameters = _invokedTypeParameters(argument);
      if (typeParameters.contains(declared.element)) return null;
    }
    return parameter.type;
  }

  /// `TypeName(...)` / `TypeName.named(...)` → `.new(...)` / `.named(...)`.
  SourceEdit? _constructorEdit(
    InstanceCreationExpression node,
    DartType context,
  ) {
    final written = node.staticType;
    if (written == null || !_sameType(context, written)) return null;

    final constructorName = node.constructorName;
    final name = constructorName.name;
    final replacement = name == null ? '.new' : '.${name.name}';

    // `const` is preserved (`const .new(...)`); a redundant `new` is dropped.
    final keyword = node.keyword;
    final start = (keyword != null && keyword.lexeme == 'new')
        ? keyword.offset
        : constructorName.offset;
    return .new(
      offset: start,
      length: constructorName.end - start,
      replacement: replacement,
    );
  }

  /// Declared type of the field named in [initializer], resolved via the
  /// field element that the initializer's field-name identifier binds to.
  DartType? _constructorFieldType(ConstructorFieldInitializer initializer) {
    final element = initializer.fieldName.element;
    return element is FieldElement ? element.type : null;
  }

  /// The static context type at [node]'s position, or null when it cannot be
  /// derived precisely enough to guarantee a safe rewrite.
  DartType? _contextType(Expression node) {
    final parent = node.parent;
    switch (parent) {
      // `Type x = node` / `final Type f = node`.
      case VariableDeclaration() when identical(parent.initializer, node):
        final list = parent.parent;
        return list is VariableDeclarationList ? list.type?.type : null;

      // `target = node` (plain assignment): the static type written to target.
      // Compound (`+=`) and `??=` are excluded; their context is less direct.
      case AssignmentExpression()
          when identical(parent.rightHandSide, node) &&
              parent.operator.lexeme == '=':
        return parent.writeType;

      // `return node;`
      case ReturnStatement():
        return _enclosingReturnType(parent);

      // `Type f() => node;`
      case ExpressionFunctionBody() when identical(parent.expression, node):
        return _enclosingReturnType(parent);

      // `a == node` / `a != node`: only the right operand has a context type.
      case BinaryExpression()
          when (parent.operator.lexeme == '==' ||
                  parent.operator.lexeme == '!=') &&
              identical(parent.rightOperand, node):
        return parent.leftOperand.staticType;

      // Positional argument.
      case ArgumentList():
        return _argumentContext(node);

      // Named argument `label: node`.
      case NamedArgument() when identical(parent.argumentExpression, node):
        return _argumentContext(parent);

      // `pattern => node` in a switch expression: inherits the switch's context.
      case SwitchExpressionCase() when identical(parent.expression, node):
        final switchExpr = parent.parent;
        return switchExpr is SwitchExpression ? _contextType(switchExpr) : null;

      // `case node:` in a switch statement: the scrutinee's type.
      case ConstantPattern() when identical(parent.expression, node):
        return _patternMatchedType(parent);

      // List element.
      case ListLiteral():
        return _listElementType(parent);

      // Set element.
      case SetOrMapLiteral():
        final type = _contextType(parent);
        return type is InterfaceType &&
                type.isDartCoreSet &&
                type.typeArguments.length == 1
            ? type.typeArguments.first
            : null;

      // Map key / value (climb through any control-flow wrappers).
      case MapLiteralEntry():
        AstNode? ancestor = parent.parent;
        while (ancestor is ForElement || ancestor is IfElement) {
          ancestor = ancestor!.parent;
        }
        if (ancestor is! SetOrMapLiteral) return null;
        final types = _mapTypes(ancestor);
        if (types == null) return null;
        if (identical(parent.value, node)) return types.value;
        if (identical(parent.key, node)) return types.key;
        return null;

      // Element that is the body of a for-collection-element.
      case ForElement() when identical(parent.body, node):
        return _enclosingCollectionElementType(parent);

      // Element that is a branch of an if-collection-element.
      case IfElement()
          when identical(parent.thenElement, node) ||
              identical(parent.elseElement, node):
        return _enclosingCollectionElementType(parent);

      // `_field = node` in a constructor initializer list.
      case ConstructorFieldInitializer()
          when identical(parent.expression, node):
        return _constructorFieldType(parent);

      default:
        return null;
    }
  }

  /// Climbs through nested ForElement/IfElement wrappers to the nearest
  /// enclosing ListLiteral or SetOrMapLiteral and returns its element type.
  DartType? _enclosingCollectionElementType(CollectionElement element) {
    AstNode? current = element.parent;
    while (current is ForElement || current is IfElement) {
      current = current!.parent;
    }
    if (current is ListLiteral) return _listElementType(current);
    if (current is SetOrMapLiteral) {
      final downward = _contextType(current);
      if (downward is InterfaceType &&
          downward.isDartCoreSet &&
          downward.typeArguments.length == 1) {
        return downward.typeArguments.first;
      }
      final explicit = current.typeArguments;
      if (explicit != null && explicit.arguments.length == 1) {
        return explicit.arguments.first.type;
      }
    }
    return null;
  }

  /// Declared return type of the nearest enclosing synchronous, non-generator
  /// function, or null when it is absent (inferred) or the body is async/*.
  DartType? _enclosingReturnType(AstNode from) {
    AstNode? current = from;
    while (current != null && current is! FunctionBody) {
      current = current.parent;
    }
    if (current is! FunctionBody) return null;
    if (!current.isSynchronous || current.isGenerator) return null;

    final owner = current.parent;
    if (owner is MethodDeclaration) return owner.returnType?.type;
    if (owner is FunctionExpression) {
      final declaration = owner.parent;
      // A bare function expression (closure) has an inferred return type.
      return declaration is FunctionDeclaration
          ? declaration.returnType?.type
          : null;
    }
    return null;
  }

  /// Type parameters of the generic element being invoked at [argument]'s call.
  List<TypeParameterElement> _invokedTypeParameters(Argument argument) {
    final argumentList = argument.parent;
    if (argumentList is! ArgumentList) return const [];
    final invocation = argumentList.parent;
    if (invocation is MethodInvocation) {
      final element = invocation.methodName.element;
      if (element is ExecutableElement) return element.typeParameters;
    }
    // Constructor type parameters belong to the class and are fixed by the
    // created type, never inferred purely from the argument here.
    return const [];
  }

  bool _isStaticMember(Element? element) => switch (element) {
    FieldElement(:final isStatic) => isStatic,
    GetterElement(:final isStatic) => isStatic,
    MethodElement(:final isStatic) => isStatic,
    _ => false,
  };

  /// Element type of a list literal: downward context, else explicit `<T>`,
  /// else the type inferred from its own elements.
  DartType? _listElementType(ListLiteral list) {
    final downward = _contextType(list);
    if (downward is InterfaceType &&
        (downward.isDartCoreList || downward.isDartCoreSet) &&
        downward.typeArguments.length == 1) {
      return downward.typeArguments.first;
    }

    final explicit = list.typeArguments;
    if (explicit != null && explicit.arguments.length == 1) {
      return explicit.arguments.first.type;
    }

    final inferred = list.staticType;
    return inferred is InterfaceType && inferred.typeArguments.length == 1
        ? inferred.typeArguments.first
        : null;
  }

  /// Key/value types of a map literal when they are known from a downward
  /// context or explicit `<K, V>`; null otherwise (no inference fallback).
  ({DartType key, DartType value})? _mapTypes(SetOrMapLiteral map) {
    final downward = _contextType(map);
    if (downward is InterfaceType &&
        downward.isDartCoreMap &&
        downward.typeArguments.length == 2) {
      return (key: downward.typeArguments[0], value: downward.typeArguments[1]);
    }

    final explicit = map.typeArguments;
    if (explicit != null && explicit.arguments.length == 2) {
      final key = explicit.arguments[0].type;
      final value = explicit.arguments[1].type;
      if (key != null && value != null) return (key: key, value: value);
    }
    return null;
  }

  /// The matched value's type for a constant pattern in a `switch`, whether the
  /// pattern is a `case <pattern>:` in a switch statement or a `<pattern> =>`
  /// arm in a switch expression. Either way the matched value is the scrutinee.
  ///
  /// Walks up through `||`/`&&` and parentheses so a constant inside a combined
  /// pattern (`A || B`) is matched against the scrutinee too.
  DartType? _patternMatchedType(ConstantPattern pattern) {
    AstNode? node = pattern.parent;
    while (node is LogicalOrPattern ||
        node is LogicalAndPattern ||
        node is ParenthesizedPattern) {
      node = node!.parent;
    }
    if (node is! GuardedPattern) return null;

    final caseNode = node.parent;
    if (caseNode is SwitchPatternCase) {
      final statement = caseNode.parent;
      return statement is SwitchStatement
          ? statement.expression.staticType
          : null;
    }
    if (caseNode is SwitchExpressionCase) {
      final switchExpr = caseNode.parent;
      return switchExpr is SwitchExpression
          ? switchExpr.expression.staticType
          : null;
    }
    return null;
  }

  /// Whether [context] and [written] denote the same interface type (same
  /// element and type arguments), ignoring nullability.
  bool _sameType(DartType context, DartType written) {
    if (context is! InterfaceType || written is! InterfaceType) return false;
    if (context.element != written.element) return false;
    final a = context.typeArguments;
    final b = written.typeArguments;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_sameType(a[i], b[i])) return false;
    }
    return true;
  }

  /// `TypeName.staticField` / `EnumName.value` → `.staticField` / `.value`.
  SourceEdit? _staticMemberEdit(PrefixedIdentifier node, DartType context) {
    final prefix = node.prefix.element;
    if (prefix is! InterfaceElement || prefix.typeParameters.isNotEmpty) {
      return null;
    }

    final member = node.identifier.element;
    if (!_isStaticMember(member)) return null;

    if (context is! InterfaceType || context.element != prefix) return null;

    // Drop the leading `TypeName`, keeping the `.member` that follows.
    return .new(
      offset: node.prefix.offset,
      length: node.prefix.length,
      replacement: '',
    );
  }

  /// `TypeName.staticMethod(...)` → `.staticMethod(...)`.
  SourceEdit? _staticMethodEdit(MethodInvocation node, DartType context) {
    final target = node.target;
    if (target == null) return null;

    final targetType = _typeReference(target);
    if (targetType == null || targetType.typeParameters.isNotEmpty) return null;

    final method = node.methodName.element;
    if (method is! MethodElement || !method.isStatic) return null;

    if (context is! InterfaceType || context.element != targetType) return null;

    // Drop the leading `TypeName`, keeping the `.method(...)` that follows.
    return .new(offset: target.offset, length: target.length, replacement: '');
  }

  /// The interface element [expression] names as a type (not a value), or null.
  InterfaceElement? _typeReference(Expression expression) {
    final element = switch (expression) {
      SimpleIdentifier() => expression.element,
      PrefixedIdentifier() => expression.identifier.element,
      _ => null,
    };
    return element is InterfaceElement ? element : null;
  }

  bool _wouldCollapse(Expression node, DartType context) => switch (node) {
    InstanceCreationExpression() => _constructorEdit(node, context) != null,
    MethodInvocation() => _staticMethodEdit(node, context) != null,
    PrefixedIdentifier() => _staticMemberEdit(node, context) != null,
    _ => false,
  };
}
