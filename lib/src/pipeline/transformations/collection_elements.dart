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
/// **Off by default.** This rewrites a run of statements into a single
/// expression, which is a much larger structural change than the other passes
/// make, so it is opt-in via `--collection-elements`.
///
/// The rewrite is applied only when ALL of the following hold:
///   * the local is declared with an **empty** list or set literal, so nothing
///     already in it can be reordered;
///   * every statement in the run is `local.add(x)`, `local.addAll(xs)`, an
///     `if` (with no `else`) wrapping exactly one of those, or a `for` wrapping
///     exactly one of those. The run stops at the first statement that is not,
///     so an unrelated statement in the middle simply ends it rather than being
///     stepped over;
///   * the local is never mentioned inside the run other than as the receiver of
///     those calls. `items.add(items.length)` reads the collection while it is
///     being built, which a single literal cannot express; and
///   * no statement in the run carries a comment, which the single replacement
///     span would otherwise drop.
///
/// Evaluation order is preserved exactly: the elements are emitted in statement
/// order, and each guard and iterable stays in front of what it guards.
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

    // Splice the elements between the literal's brackets. The bracket is not
    // the literal's first token when it carries a type argument (`<int>[]`
    // begins at `<`), so take it from the node rather than from beginToken.
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
  (Token, Token)? _brackets(Expression literal) => switch (literal) {
    ListLiteral(:final leftBracket, :final rightBracket) => (
      leftBracket,
      rightBracket,
    ),
    SetOrMapLiteral(:final leftBracket, :final rightBracket) => (
      leftBracket,
      rightBracket,
    ),
    _ => null,
  };

  /// True for `[]`, `{}`, `<T>[]`, `<T>{}` with nothing inside.
  bool _isEmptyCollectionLiteral(Expression? expression) =>
      switch (expression) {
        ListLiteral(:final elements) => elements.isEmpty,
        SetOrMapLiteral(:final elements) => elements.isEmpty,
        _ => false,
      };

  /// Renders [statement] as a collection element, or null when it is not one of
  /// the recognised build steps for [target].
  String? _element(Statement statement, Element target) {
    if (statement is ExpressionStatement) {
      return _addElement(statement.expression, target);
    }
    if (statement is IfStatement) {
      // An `else` would need a collection-`if`/`else`, whose second branch is
      // not part of the same build step; keeping to the guard-only form is what
      // makes the ordering argument simple.
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
    // Reading the collection while building it cannot be expressed in a literal.
    if (_mentions(argument, target)) return null;

    return switch (expression.methodName.name) {
      'add' => _text(argument),
      'addAll' => '...${_text(argument)}',
      _ => null,
    };
  }

  /// The single statement [statement] holds, unwrapping a one-statement block.
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
