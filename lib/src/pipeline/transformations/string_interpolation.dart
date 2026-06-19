import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/type.dart';

import '../../engine/source_edit.dart';
import '../transformation.dart';

bool _isStringType(DartType? type) => type?.isDartCoreString == true;

sealed class _Segment {}

final class _LiteralSegment extends _Segment {
  final String value;
  _LiteralSegment(this.value);
}

final class _ExpressionSegment extends _Segment {
  final Expression node;
  final bool needsBraces;
  _ExpressionSegment(this.node, {required this.needsBraces});
}

/// Rewrites string concatenation chains into string interpolation.
///
/// Before: `'Hello, ' + name + '!'`
/// After:  `'Hello, $name!'`
final class StringInterpolation implements Transformation {
  @override
  final bool enabled;

  const StringInterpolation({required this.enabled});

  @override
  String get name => 'string-interpolation';

  @override
  Future<List<SourceEdit>> editsFor(ResolvedUnitResult unit) async {
    final visitor = _StringInterpolationVisitor(unit.content);
    unit.unit.accept(visitor);
    return visitor.edits;
  }
}

class _StringInterpolationVisitor extends RecursiveAstVisitor<void> {
  final String source;
  final List<SourceEdit> edits = [];

  _StringInterpolationVisitor(this.source);

  @override
  void visitBinaryExpression(BinaryExpression node) {
    // Skip inner nodes of a string-concatenation chain; only process the root.
    final parent = node.parent;
    if (parent is BinaryExpression &&
        parent.operator.lexeme == '+' &&
        _isStringType(parent.staticType)) {
      super.visitBinaryExpression(node);
      return;
    }

    final segments = _flatten(node);
    if (segments == null ||
        segments.length <= 1 ||
        !segments.any((s) => s is _ExpressionSegment)) {
      super.visitBinaryExpression(node);
      return;
    }

    edits.add(SourceEdit(
      offset: node.offset,
      length: node.length,
      replacement: _buildInterpolation(segments),
    ));
    // Do not recurse — the whole chain is handled as a unit.
  }

  /// Flattens a concatenation chain into a list of segments, or returns
  /// `null` if any part of the chain is not safe to rewrite.
  List<_Segment>? _flatten(Expression expr) {
    if (expr is BinaryExpression) {
      if (expr.operator.lexeme != '+') return null;
      if (!_isStringType(expr.staticType)) return null;
      final left = _flatten(expr.leftOperand);
      if (left == null) return null;
      final right = _flatten(expr.rightOperand);
      if (right == null) return null;
      return [...left, ...right];
    }

    if (expr is SimpleStringLiteral) {
      return [_LiteralSegment(expr.value)];
    }

    // Non-literal: must be String-typed and side-effect-free.
    if (!_isStringType(expr.staticType)) return null;
    if (!_isSafe(expr)) return null;

    return [_ExpressionSegment(expr, needsBraces: expr is! SimpleIdentifier)];
  }

  /// Returns true when [expr] is a side-effect-free String reference whose
  /// source text can be moved into an interpolation without changing semantics.
  bool _isSafe(Expression expr) {
    if (expr is SimpleIdentifier) return true;
    if (expr is PrefixedIdentifier) return true;
    if (expr is PropertyAccess) return expr.realTarget is SimpleIdentifier;
    return false;
  }

  String _buildInterpolation(List<_Segment> segments) {
    final buf = StringBuffer("'");
    for (var i = 0; i < segments.length; i++) {
      switch (segments[i]) {
        case _LiteralSegment(:final value):
          buf.write(_escapeLiteralContent(value));
        case _ExpressionSegment(:final node, needsBraces: final hasBraces):
          final exprSrc = source.substring(node.offset, node.end);
          final useBraces = hasBraces || _nextStartsWithWordChar(segments, i);
          buf.write(useBraces ? '\${$exprSrc}' : '\$$exprSrc');
      }
    }
    buf.write("'");
    return buf.toString();
  }

  /// Escapes [value] so it is safe to embed in a single-quoted interpolated
  /// string literal.
  String _escapeLiteralContent(String value) {
    final buf = StringBuffer();
    for (final rune in value.runes) {
      switch (rune) {
        case 0x5c: // \
          buf.write(r'\\');
        case 0x27: // '
          buf.write(r"\'");
        case 0x24: // $
          buf.write(r'\$');
        case 0x0a: // newline
          buf.write(r'\n');
        case 0x0d: // carriage return
          buf.write(r'\r');
        case 0x09: // tab
          buf.write(r'\t');
        default:
          buf.writeCharCode(rune);
      }
    }
    return buf.toString();
  }

  /// Returns true when the segment after index [i] begins with a word
  /// character, which would make a bare `$identifier` ambiguous.
  bool _nextStartsWithWordChar(List<_Segment> segments, int i) {
    if (i + 1 >= segments.length) return false;
    final next = segments[i + 1];
    if (next is _LiteralSegment && next.value.isNotEmpty) {
      final c = next.value.codeUnitAt(0);
      return (c >= 0x41 && c <= 0x5a) || // A-Z
          (c >= 0x61 && c <= 0x7a) || // a-z
          (c >= 0x30 && c <= 0x39) || // 0-9
          c == 0x5f; // _
    }
    return false;
  }
}
