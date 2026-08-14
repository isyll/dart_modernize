import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';

import '../../engine/source_edit.dart';
import '../transformation.dart';

/// Folds a step-by-step collection build into one literal using collection-`if`
/// and collection-`for` elements.
///
/// ```dart
/// // before
/// final items = <Widget>[];
/// items.add(header);
/// if (showBody) items.add(body);
/// for (final s in sections) items.add(s);
///
/// // after
/// final items = <Widget>[
///   header,
///   if (showBody) body,
///   for (final s in sections) s,
/// ];
/// ```
///
/// Off by default, because it turns several statements into one expression,
/// a bigger change than the other passes make. Switch it on with
/// `--collection-elements`.
///
/// Skipped when:
///   * the literal is not empty to start with;
///   * a statement is not `add`/`addAll`, an `else`-less `if` around one, or a
///     `for` around one. The run simply stops at that statement;
///   * the run reads the collection while building it, as in
///     `items.add(items.length)`, which a literal cannot express;
///   * a statement carries a comment, which the rewrite would drop.
///
/// Elements come out in statement order, so evaluation order does not change.
final class CollectionElements implements Transformation {
  const CollectionElements({required this.enabled});

  @override
  final bool enabled;

  @override
  String get name => 'collection-elements';

  @override
  Future<List<SourceEdit>> editsFor(ResolvedUnitResult unit) async {
    final visitor = _CollectionElementsVisitor(unit.content);
    unit.unit.accept(visitor);
    return visitor.edits;
  }
}

class _CollectionElementsVisitor extends RecursiveAstVisitor<void> {
  _CollectionElementsVisitor(this.source);
  final String source;

  final edits = <SourceEdit>[];

  @override
  void visitBlock(Block node) {
    super.visitBlock(node);
    final statements = node.statements;
    for (var i = 0; i < statements.length; i++) {
      _collectAt(statements, i);
    }
  }

  void _collectAt(NodeList<Statement> statements, int index) {
    final declaration = statements[index];
    if (declaration is! VariableDeclarationStatement) return;
    final variables = declaration.variables;
    if (variables.variables.length != 1) return;
    if (variables.keyword == null) return;

    final variable = variables.variables.single;
    final literal = variable.initializer;
    if (!_isEmptyCollectionLiteral(literal)) return;

    final target = variable.declaredFragment?.element;
    if (target == null) return;

    final elements = <String>[];
    var end = index;
    for (var i = index + 1; i < statements.length; i++) {
      final statement = statements[i];
      if (statement.beginToken.precedingComments != null) break;
      final element = _element(statement, target);
      if (element == null) break;
      elements.add(element);
      end = i;
    }
    if (elements.isEmpty) return;

    // Put the elements between the brackets. With a type argument the literal
    // starts at `<`, not `[`, so read the bracket off the node.
    final brackets = _brackets(literal!);
    if (brackets == null) return;
    final (leftBracket, rightBracket) = brackets;

    edits.add(
      .new(
        offset: declaration.offset,
        length: statements[end].end - declaration.offset,
        replacement:
            '${source.substring(declaration.offset, leftBracket.end)}'
            '${elements.join(', ')}'
            '${rightBracket.lexeme};',
      ),
    );
  }

  /// The literal's opening and closing bracket tokens.
  (Token, Token)? _brackets(Expression literal) {
    if (literal is ListLiteral) {
      return (literal.leftBracket, literal.rightBracket);
    }
    if (literal is SetOrMapLiteral) {
      return (literal.leftBracket, literal.rightBracket);
    }
    return null;
  }

  /// True for `[]`, `{}`, `<T>[]`, `<T>{}` with nothing inside.
  bool _isEmptyCollectionLiteral(Expression? expression) {
    if (expression is ListLiteral) return expression.elements.isEmpty;
    if (expression is SetOrMapLiteral) return expression.elements.isEmpty;
    return false;
  }

  /// Renders [statement] as a collection element, or null when it is not one of
  /// the recognised build steps for [target].
  String? _element(Statement statement, Element target) {
    if (statement is ExpressionStatement) {
      return _addElement(statement.expression, target);
    }
    if (statement is IfStatement) {
      // Only the guard form. An `else` adds a second branch to reason about.
      if (statement.elseStatement != null) return null;
      final inner = _soleStatement(statement.thenStatement);
      if (inner == null) return null;
      final element = _element(inner, target);
      if (element == null) return null;
      final condition = _text(statement.expression);
      if (_mentions(statement.expression, target)) return null;
      return 'if ($condition) $element';
    }
    if (statement is ForStatement) {
      final inner = _soleStatement(statement.body);
      if (inner == null) return null;
      final element = _element(inner, target);
      if (element == null) return null;
      if (_mentions(statement.forLoopParts, target)) return null;
      final parts = _text(statement.forLoopParts);
      return 'for ($parts) $element';
    }
    return null;
  }

  /// Renders `target.add(x)` as `x` and `target.addAll(xs)` as `...xs`.
  String? _addElement(Expression expression, Element target) {
    if (expression is! MethodInvocation) return null;
    final receiver = expression.target;
    if (receiver is! SimpleIdentifier || receiver.element != target) {
      return null;
    }

    final arguments = expression.argumentList.arguments;
    if (arguments.length != 1) return null;
    final argument = arguments.single;
    if (argument is NamedArgument) return null;
    // A literal cannot read the collection it is building.
    if (_mentions(argument, target)) return null;

    final method = expression.methodName.name;
    if (method == 'add') return _text(argument);
    if (method == 'addAll') return '...${_text(argument)}';
    return null;
  }

  /// The one statement inside [statement], unwrapping a single-statement block.
  Statement? _soleStatement(Statement statement) {
    if (statement is Block) {
      return statement.statements.length == 1
          ? statement.statements.single
          : null;
    }
    return statement;
  }

  bool _mentions(AstNode node, Element target) {
    final finder = _ReferenceFinder(target);
    node.accept(finder);
    return finder.found;
  }

  String _text(AstNode node) => source.substring(node.offset, node.end);
}

class _ReferenceFinder extends RecursiveAstVisitor<void> {
  _ReferenceFinder(this.target);
  final Element target;

  bool found = false;

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    super.visitSimpleIdentifier(node);
    if (node.element == target) found = true;
  }
}
