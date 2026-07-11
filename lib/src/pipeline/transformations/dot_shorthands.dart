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
/// or field, plain assignment target, return type, `yield` in a generator,
/// argument slot, collection element, record field, equality right-hand side,
/// `??` right-hand side, switch case, switch pattern). Wherever the context type
/// cannot be derived precisely, with `var`, `dynamic`, `Object`, an inferred
/// type variable, a supertype, or the left of `==`, the code is left untouched.
///
/// The head of a selector chain is collapsed too. In `DateTime.now().toUtc()`
/// or `DateTime.tryParse(s)?.toUtc()` the dot-shorthand head resolves against
/// the context type of the *whole* chain, not the type the head alone produces,
/// so the context flows up through the enclosing selectors (`.method(...)`,
/// `.getter`, `[index]`, `!`) to wherever the chain sits:
///
///   * `expiry.difference(DateTime.now().toUtc())` → `.difference(.now()...)`
///   * `return DateTime.tryParse(s)?.toUtc();`     → `return .tryParse(s)...`
///   * `Color c = Color.values.first;`             → `Color c = .values.first;`
///
/// Only the leftmost target inherits the chain's context; the per-edit checks
/// still require the head's own referenced type to equal that context, so an
/// intermediate selector that changes the type blocks the collapse.
///
/// Record literals are supported too. A positional field takes its context from
/// the matching positional field of the record's own context type, and a named
/// field from the same-named field. When a list of records has no element type
/// to fall back on, the inferred record element type is hoisted onto the literal
/// (`<(Foo, String)>[...]`) so the field shorthands have a context to resolve
/// against, but only when every field of that record type is precise.
final class DotShorthands implements Transformation {
  const DotShorthands({required this.enabled});

  @override
  final bool enabled;

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
  final edits = <SourceEdit>[];

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

    // A record element type is hoisted only when every field is precise, so the
    // display string reproduces the static type exactly and the field shorthands
    // have a real context to resolve against (matching [_recordFieldContext]).
    if (elementType is RecordType && !_isPreciseRecordType(elementType)) return;

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

  /// Whether any field of [record] would collapse to a shorthand, given [type]
  /// as the record's context type. Positional fields are matched by index,
  /// named fields by name; nested record fields recurse through [_wouldCollapse].
  bool _anyRecordFieldCollapses(RecordLiteral record, RecordType type) {
    if (!_isPreciseRecordType(type)) return false;

    var index = 0;
    for (final field in record.fields) {
      final DartType? fieldContext;
      if (field is RecordLiteralNamedField) {
        fieldContext = _namedFieldType(type, field.name.lexeme);
      } else {
        final positional = type.positionalFields;
        fieldContext = index < positional.length
            ? positional[index].type
            : null;
        index++;
      }
      if (fieldContext != null &&
          _wouldCollapse(field.fieldExpression, fieldContext)) {
        return true;
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

      // `yield node;` in a generator: the element type of the produced sequence.
      // `yield* node` is excluded because it yields a whole sequence, not one
      // element.
      case YieldStatement()
          when identical(parent.expression, node) && parent.star == null:
        return _enclosingYieldType(parent);

      // `a == node` / `a != node`: only the right operand has a context type.
      case BinaryExpression()
          when (parent.operator.lexeme == '==' ||
                  parent.operator.lexeme == '!=') &&
              identical(parent.rightOperand, node):
        return parent.leftOperand.staticType;

      // `a ?? node`: the right operand takes the whole `??` expression's own
      // context type (that is where a `??` pushes its context).
      case BinaryExpression()
          when parent.operator.lexeme == '??' &&
              identical(parent.rightOperand, node):
        return _contextType(parent);

      // Positional argument.
      case ArgumentList():
        return _argumentContext(node);

      // Named argument `label: node`.
      case NamedArgument() when identical(parent.argumentExpression, node):
        return _argumentContext(parent);

      // A branch of a `?:` conditional: takes the conditional's own context.
      case ConditionalExpression()
          when identical(parent.thenExpression, node) ||
              identical(parent.elseExpression, node):
        return _contextType(parent);

      // Head of a selector chain: `node.method(...)`, `node.getter`,
      // `node[index]`, `node!`. A dot-shorthand head resolves against the
      // context type of the whole chain, so climb to the enclosing selector and
      // take its context. Recursion carries it up an arbitrarily long chain to
      // wherever it ends. The per-edit checks still require the head's own
      // referenced type to equal that context, so a selector that changes the
      // type (`int.parse(s).toDouble()` in a `num` context) blocks the collapse.
      case MethodInvocation() when identical(parent.target, node):
        return _contextType(parent);
      case PropertyAccess() when identical(parent.target, node):
        return _contextType(parent);
      case IndexExpression() when identical(parent.target, node):
        return _contextType(parent);
      case PostfixExpression()
          when parent.operator.lexeme == '!' && identical(parent.operand, node):
        return _contextType(parent);

      // `pattern => node` in a switch expression: takes the switch's context.
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
        var ancestor = parent.parent;
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

      // Field of a record literal. A positional field's expression is itself
      // the RecordLiteralField, so its parent is the record; a named field's
      // expression is wrapped, so its parent is the RecordLiteralNamedField.
      case RecordLiteral():
        return _recordFieldContext(parent, node);
      case RecordLiteralNamedField()
          when identical(parent.fieldExpression, node):
        final record = parent.parent;
        return record is RecordLiteral
            ? _recordFieldContext(record, node)
            : null;

      default:
        return null;
    }
  }

  /// Climbs through nested ForElement/IfElement wrappers to the nearest
  /// enclosing ListLiteral or SetOrMapLiteral and returns its element type.
  DartType? _enclosingCollectionElementType(CollectionElement element) {
    var current = element.parent;
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

  /// The value type a `return e;` or `=> e` produces in the enclosing function.
  ///
  /// For a sync function it is the declared return type. For an `async` function
  /// it is `T` from a `Future<T>` return type. Generators and closures (whose
  /// return type is inferred) have no usable context, so they give null.
  DartType? _enclosingReturnType(AstNode from) {
    AstNode? current = from;
    while (current != null && current is! FunctionBody) {
      current = current.parent;
    }
    if (current is! FunctionBody) return null;
    if (current.isGenerator) return null;

    final owner = current.parent;
    final DartType? declared;
    if (owner is MethodDeclaration) {
      declared = owner.returnType?.type;
    } else if (owner is FunctionExpression &&
        owner.parent is FunctionDeclaration) {
      declared = (owner.parent as FunctionDeclaration).returnType?.type;
    } else {
      declared = null;
    }
    if (declared == null) return null;

    if (current.isAsynchronous) {
      return declared is InterfaceType &&
              declared.isDartAsyncFuture &&
              declared.typeArguments.length == 1
          ? declared.typeArguments.first
          : null;
    }
    return declared;
  }

  /// The element type a `yield e;` produces: `T` from the enclosing generator's
  /// `Iterable<T>` (`sync*`) or `Stream<T>` (`async*`) return type. Null when the
  /// return type is not a single-argument sequence of the expected kind, or the
  /// generator's return type is inferred (a closure).
  DartType? _enclosingYieldType(YieldStatement statement) {
    AstNode? current = statement;
    while (current != null && current is! FunctionBody) {
      current = current.parent;
    }
    if (current is! FunctionBody || !current.isGenerator) return null;

    final owner = current.parent;
    final DartType? declared;
    if (owner is MethodDeclaration) {
      declared = owner.returnType?.type;
    } else if (owner is FunctionExpression &&
        owner.parent is FunctionDeclaration) {
      declared = (owner.parent as FunctionDeclaration).returnType?.type;
    } else {
      declared = null;
    }
    if (declared is! InterfaceType || declared.typeArguments.length != 1) {
      return null;
    }

    final matches = current.isAsynchronous
        ? declared.isDartAsyncStream
        : declared.isDartCoreIterable;
    return matches ? declared.typeArguments.first : null;
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
    // A constructor with no explicit `<...>` infers the class's type arguments
    // from its own arguments, so a parameter typed by one of those type
    // variables offers no downward context (collapsing it would erase the only
    // thing the type could be inferred from). With explicit `<...>` the type is
    // fixed, so the arguments are safe to collapse.
    if (invocation is InstanceCreationExpression &&
        invocation.constructorName.type.typeArguments == null) {
      final cls = invocation.constructorName.element?.enclosingElement;
      if (cls is InterfaceElement) return cls.typeParameters;
    }
    return const [];
  }

  /// Whether every field type of [type] is precise enough that hoisting the
  /// record's display string reproduces the static type exactly and each field
  /// shorthand has a concrete context. Rejects a field (anywhere in the record,
  /// recursively) that no shorthand could ever resolve against.
  bool _isPreciseRecordType(RecordType type) {
    for (final field in type.positionalFields) {
      if (!_isPreciseType(field.type)) return false;
    }
    for (final field in type.namedFields) {
      if (!_isPreciseType(field.type)) return false;
    }
    return true;
  }

  /// Whether [type] is a fully resolved, precise type (see [_isPreciseRecordType]
  /// for why this matters). Rejects the same catch-all/unresolved types the pass
  /// never rewrites against elsewhere (`dynamic`, `Object`, `Null`, an inferred
  /// type variable, an invalid type). Descends into record fields and interface
  /// type arguments.
  bool _isPreciseType(DartType type) {
    if (type is DynamicType || type is InvalidType) return false;
    if (type is TypeParameterType) return false;
    if (type.isDartCoreNull || type.isDartCoreObject) return false;
    if (type is RecordType) return _isPreciseRecordType(type);
    if (type is InterfaceType) {
      for (final argument in type.typeArguments) {
        if (!_isPreciseType(argument)) return false;
      }
    }
    return true;
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

  /// The type of the named field called [name] in [type], or null if absent.
  DartType? _namedFieldType(RecordType type, String name) {
    for (final field in type.namedFields) {
      if (field.name == name) return field.type;
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
    var node = pattern.parent;
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

  /// Context type for the field of [record] whose value expression is [node]:
  /// the matching field of the record's own (precise) context type. Positional
  /// fields match by index, named fields by name. Returns null when the record's
  /// context type is not a precise record type, so an imprecise record neither
  /// shortens its fields nor is hoisted (see [_annotateInferredList]).
  DartType? _recordFieldContext(RecordLiteral record, Expression node) {
    final recordType = _contextType(record);
    if (recordType is! RecordType || !_isPreciseRecordType(recordType)) {
      return null;
    }

    var index = 0;
    for (final field in record.fields) {
      final isNamed = field is RecordLiteralNamedField;
      if (identical(field.fieldExpression, node)) {
        if (isNamed) return _namedFieldType(recordType, field.name.lexeme);
        final positional = recordType.positionalFields;
        return index < positional.length ? positional[index].type : null;
      }
      if (!isNamed) index++;
    }
    return null;
  }

  /// Whether two record types are the same: equal record nullability, the same
  /// number of positional fields whose types are pairwise [_sameType], and the
  /// same set of named fields (matched by name, never by position) whose types
  /// are [_sameType].
  bool _sameRecordType(RecordType context, RecordType written) {
    if (context.nullabilitySuffix != written.nullabilitySuffix) return false;

    final cp = context.positionalFields;
    final wp = written.positionalFields;
    if (cp.length != wp.length) return false;
    for (var i = 0; i < cp.length; i++) {
      if (!_sameType(cp[i].type, wp[i].type)) return false;
    }

    final cn = context.namedFields;
    final wn = written.namedFields;
    if (cn.length != wn.length) return false;
    for (final field in cn) {
      final other = _namedFieldType(written, field.name);
      if (other == null || !_sameType(field.type, other)) return false;
    }
    return true;
  }

  /// Whether [context] and [written] denote the same type: the same interface
  /// type (same element and type arguments, ignoring nullability), or the same
  /// record type (see [_sameRecordType]).
  bool _sameType(DartType context, DartType written) {
    if (context is RecordType && written is RecordType) {
      return _sameRecordType(context, written);
    }
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
    RecordLiteral() =>
      context is RecordType && _anyRecordFieldCollapses(node, context),
    _ => false,
  };
}
