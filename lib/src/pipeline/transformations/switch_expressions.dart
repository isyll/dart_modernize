import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

import '../../engine/source_edit.dart';
import '../transformation.dart';

/// Rewrites an eligible statement-style `switch` as a switch expression.
///
/// Eligible switches uniformly either (a) assign the same single variable in
/// every arm, or (b) return a value in every arm (throw counts as producing a
/// value in both shapes). Empty fallthrough cases collapse to logical-or
/// patterns (`A || B`). `default` maps to `_`. Exhaustive enum switches with
/// no `default` keep their exact patterns.
///
/// For the assignment shape, when the target variable is declared immediately
/// before the switch with no initializer and no intervening use, the
/// declaration is folded into `final x = switch (...) {...};`. Otherwise the
/// switch is replaced with `x = switch (...) {...};` in place.
final class SwitchExpressions implements Transformation {
  @override
  final bool enabled;

  const SwitchExpressions({required this.enabled});

  @override
  String get name => 'switch-expressions';

  @override
  Future<List<SourceEdit>> editsFor(ResolvedUnitResult unit) async {
    final visitor = _SwitchExprVisitor(unit.content);
    unit.unit.accept(visitor);
    return visitor.edits;
  }
}

// ---------------------------------------------------------------------------
// Internal data model
// ---------------------------------------------------------------------------

sealed class _Pattern {}

final class _CasePattern extends _Pattern {
  final Expression expr;
  _CasePattern(this.expr);
}

final class _DefaultPattern extends _Pattern {}

sealed class _ArmBody {}

final class _AssignBody extends _ArmBody {
  final SimpleIdentifier lhs;
  final String rhsText;
  _AssignBody(this.lhs, this.rhsText);
}

final class _ReturnBody extends _ArmBody {
  final String exprText;
  _ReturnBody(this.exprText);
}

final class _ThrowBody extends _ArmBody {
  final String throwText;
  _ThrowBody(this.throwText);
}

final class _Arm {
  final List<_Pattern> patterns;
  final _ArmBody body;
  bool get hasDefault => patterns.any((p) => p is _DefaultPattern);
  _Arm({required this.patterns, required this.body});
}

// ---------------------------------------------------------------------------
// Visitor
// ---------------------------------------------------------------------------

class _SwitchExprVisitor extends RecursiveAstVisitor<void> {
  final String source;
  final List<SourceEdit> edits = [];

  _SwitchExprVisitor(this.source);

  @override
  void visitSwitchStatement(SwitchStatement node) {
    _tryRewrite(node);
    super.visitSwitchStatement(node);
  }

  void _tryRewrite(SwitchStatement stmt) {
    final arms = _collectArms(stmt);
    if (arms == null || arms.isEmpty) return;

    final shape = _determineShape(arms);
    if (shape == null) return;

    if (!_isExhaustive(stmt, arms)) return;

    _buildEdit(stmt, arms, shape);
  }

  // -------------------------------------------------------------------------
  // Arm collection
  // -------------------------------------------------------------------------

  List<_Arm>? _collectArms(SwitchStatement stmt) {
    final result = <_Arm>[];
    final currentPatterns = <_Pattern>[];

    for (final member in stmt.members) {
      if (member.labels.isNotEmpty) return null;

      if (member is SwitchPatternCase) {
        // Reject guarded patterns (`case x when cond:`).
        if (member.guardedPattern.whenClause != null) return null;
        // Only plain constant patterns (`case 'A':`, `case Enum.value:`, etc.)
        // are equivalent to old-style `case expr:`. Complex patterns (object,
        // list, record, …) are already idiomatic and must not be rewritten.
        final pattern = member.guardedPattern.pattern;
        if (pattern is! ConstantPattern) return null;
        currentPatterns.add(_CasePattern(pattern.expression));
        if (member.statements.isEmpty) continue; // fallthrough
        final body = _parseBody(member.statements);
        if (body == null) return null;
        result.add(_Arm(patterns: List.of(currentPatterns), body: body));
        currentPatterns.clear();
      } else if (member is SwitchCase) {
        // Pre-Dart-3 AST node: handle for completeness.
        currentPatterns.add(_CasePattern(member.expression));
        if (member.statements.isEmpty) continue;
        final body = _parseBody(member.statements);
        if (body == null) return null;
        result.add(_Arm(patterns: List.of(currentPatterns), body: body));
        currentPatterns.clear();
      } else if (member is SwitchDefault) {
        // default: preceded by fallthrough cases, reject (rare, conservative).
        if (currentPatterns.isNotEmpty) return null;
        if (member.statements.isEmpty) return null;
        currentPatterns.add(_DefaultPattern());
        final body = _parseBody(member.statements);
        if (body == null) return null;
        result.add(_Arm(patterns: List.of(currentPatterns), body: body));
        currentPatterns.clear();
      }
    }

    // Trailing empty cases (no body after them) are ineligible.
    if (currentPatterns.isNotEmpty) return null;
    return result;
  }

  /// Parses the statement list of one case arm.
  ///
  /// Valid shapes:
  ///   - `[return expr;]`
  ///   - `[throw expr;]`  (ExpressionStatement wrapping ThrowExpression)
  ///   - `[x = val;]`     (assignment, no trailing break : default arm style)
  ///   - `[x = val; break;]`  (assignment + unlabeled break)
  _ArmBody? _parseBody(NodeList<Statement> stmts) {
    if (stmts.isEmpty) return null;

    if (stmts.length == 1) {
      final stmt = stmts.first;
      if (stmt is ReturnStatement) {
        final expr = stmt.expression;
        if (expr == null) return null;
        return _ReturnBody(source.substring(expr.offset, expr.end));
      }
      if (stmt is ExpressionStatement) {
        final expr = stmt.expression;
        if (expr is ThrowExpression) {
          return _ThrowBody(source.substring(expr.offset, expr.end));
        }
        if (expr is AssignmentExpression && expr.operator.lexeme == '=') {
          final lhs = expr.leftHandSide;
          if (lhs is! SimpleIdentifier) return null;
          return _AssignBody(
            lhs,
            source.substring(expr.rightHandSide.offset, expr.rightHandSide.end),
          );
        }
      }
      return null;
    }

    if (stmts.length == 2) {
      final first = stmts.first;
      final last = stmts.last;
      if (last is BreakStatement &&
          last.label == null &&
          first is ExpressionStatement) {
        final expr = first.expression;
        if (expr is AssignmentExpression && expr.operator.lexeme == '=') {
          final lhs = expr.leftHandSide;
          if (lhs is! SimpleIdentifier) return null;
          return _AssignBody(
            lhs,
            source.substring(expr.rightHandSide.offset, expr.rightHandSide.end),
          );
        }
      }
      return null;
    }

    return null; // Three or more statements.
  }

  // -------------------------------------------------------------------------
  // Shape determination
  // -------------------------------------------------------------------------

  // Returns 'assign:<element>' or 'return', or null if mixed / invalid.
  String? _determineShape(List<_Arm> arms) {
    Element? assignTarget;
    var hasReturn = false;

    for (final arm in arms) {
      switch (arm.body) {
        case _AssignBody(lhs: final lhs):
          final el = lhs.element;
          if (el == null) return null;
          if (assignTarget == null) {
            assignTarget = el;
          } else if (assignTarget != el) {
            return null; // Different targets.
          }
        case _ReturnBody():
          if (assignTarget != null) return null; // Mixed.
          hasReturn = true;
        case _ThrowBody():
          break; // Throw is compatible with both shapes.
      }
    }

    if (!hasReturn && assignTarget == null) return null; // All throws, skip.
    if (hasReturn && assignTarget != null) return null; // Mixed.
    return hasReturn ? 'return' : 'assign';
  }

  // -------------------------------------------------------------------------
  // Exhaustiveness
  // -------------------------------------------------------------------------

  bool _isExhaustive(SwitchStatement stmt, List<_Arm> arms) {
    if (arms.any((a) => a.hasDefault)) return true;
    return _isExhaustiveEnum(stmt, arms);
  }

  bool _isExhaustiveEnum(SwitchStatement stmt, List<_Arm> arms) {
    final scrutineeType = stmt.expression.staticType;
    if (scrutineeType is! InterfaceType) return false;
    final element = scrutineeType.element;
    if (element is! EnumElement) return false;

    final allConstants = element.constants.toSet();
    final covered = <FieldElement>{};

    for (final arm in arms) {
      for (final pattern in arm.patterns) {
        if (pattern is! _CasePattern) return false;
        final expr = pattern.expr;
        if (expr is! PrefixedIdentifier) return false;
        // In Dart 3, `Direction.north` resolves via a synthetic getter;
        // unwrap to the backing FieldElement to match element.constants.
        final fieldElement = _asEnumConstant(
          expr.identifier.element,
          allConstants,
        );
        if (fieldElement == null) return false;
        covered.add(fieldElement);
      }
    }
    return covered.length == allConstants.length;
  }

  FieldElement? _asEnumConstant(
    Element? rawElement,
    Set<FieldElement> constants,
  ) {
    if (rawElement is FieldElement && constants.contains(rawElement)) {
      return rawElement;
    }
    if (rawElement is GetterElement) {
      final variable = rawElement.variable;
      if (variable is FieldElement && constants.contains(variable)) {
        return variable;
      }
    }
    return null;
  }

  // -------------------------------------------------------------------------
  // Edit construction
  // -------------------------------------------------------------------------

  void _buildEdit(SwitchStatement stmt, List<_Arm> arms, String shape) {
    final indent = _leadingIndent(stmt.offset);
    final armIndent = '$indent  ';
    final scrutinee = source.substring(
      stmt.expression.offset,
      stmt.expression.end,
    );
    final armLines = arms
        .map(
          (a) =>
              '$armIndent${_patternText(a.patterns)} => ${_valueText(a.body)},',
        )
        .join('\n');
    final switchExpr = 'switch ($scrutinee) {\n$armLines\n$indent}';

    if (shape == 'return') {
      edits.add(
        SourceEdit(
          offset: stmt.offset,
          length: stmt.end - stmt.offset,
          replacement: 'return $switchExpr;',
        ),
      );
      return;
    }

    // Assignment shape: try to fold the preceding declaration.
    final targetElement = _assignTarget(arms)!;
    final preceding = _findPrecedingDecl(stmt, targetElement);

    if (preceding != null) {
      final (decl, varName) = preceding;
      edits.add(
        SourceEdit(
          offset: decl.offset,
          length: stmt.end - decl.offset,
          replacement: '${indent}final $varName = $switchExpr;',
        ),
      );
    } else {
      final varName = targetElement.name ?? '';
      if (varName.isEmpty) return;
      edits.add(
        SourceEdit(
          offset: stmt.offset,
          length: stmt.end - stmt.offset,
          replacement: '$varName = $switchExpr;',
        ),
      );
    }
  }

  String _patternText(List<_Pattern> patterns) => patterns
      .map(
        (p) => switch (p) {
          _CasePattern(expr: final e) => source.substring(e.offset, e.end),
          _DefaultPattern() => '_',
        },
      )
      .join(' || ');

  String _valueText(_ArmBody body) => switch (body) {
    _AssignBody(rhsText: final t) => t,
    _ReturnBody(exprText: final t) => t,
    _ThrowBody(throwText: final t) => t,
  };

  Element? _assignTarget(List<_Arm> arms) {
    for (final arm in arms) {
      if (arm.body case _AssignBody(lhs: final lhs)) {
        return lhs.element;
      }
    }
    return null;
  }

  /// Finds the `VariableDeclarationStatement` immediately before [stmt] in the
  /// same block that declares [targetElement] with no initializer.
  (VariableDeclarationStatement, String)? _findPrecedingDecl(
    SwitchStatement stmt,
    Element targetElement,
  ) {
    final block = stmt.parent;
    if (block is! Block) return null;

    final stmts = block.statements;
    final switchIndex = stmts.indexOf(stmt);
    if (switchIndex <= 0) return null;

    final prev = stmts[switchIndex - 1];
    if (prev is! VariableDeclarationStatement) return null;

    final vars = prev.variables;
    if (vars.variables.length != 1) return null;

    final varDecl = vars.variables.single;
    if (varDecl.initializer != null) return null;

    final element = varDecl.declaredFragment?.element;
    if (element == null || element != targetElement) return null;

    return (prev, varDecl.name.lexeme);
  }

  String _leadingIndent(int offset) {
    var pos = offset - 1;
    while (pos >= 0 && source[pos] != '\n') {
      pos--;
    }
    final lineStart = pos + 1;
    final buf = StringBuffer();
    for (var i = lineStart; i < offset; i++) {
      final ch = source[i];
      if (ch == ' ' || ch == '\t') {
        buf.write(ch);
      } else {
        break;
      }
    }
    return buf.toString();
  }
}
