/// Comment-aware source ranges for declarations.
///
/// Ported from the Dart SDK analysis server's `RangeFactory.nodeWithComments`
/// (`utilities/extensions/range_factory.dart`). The member sorter needs each
/// declaration's range to include the comments that belong to it (a leading
/// `//` comment on the line above, a trailing comment on the same line) so they
/// travel with the member when it is reordered. Documentation comments and
/// metadata are already part of the node and need no special handling.
library;

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/source/line_info.dart';

/// Returns the range of [node] extended to cover the comments attached to it.
NodeRange nodeWithComments(LineInfo lineInfo, AstNode node) {
  final beginToken = node.beginToken;
  // If the node is the first thing in the unit, leading comments are treated as
  // a file header and are never included in the range.
  final isFirstItem = beginToken == node.root.beginToken;

  final start = isFirstItem
      ? beginToken
      : _leadingComment(lineInfo, beginToken);
  final end = _trailingComment(lineInfo, node.endToken);
  return (offset: start.offset, end: end.end);
}

/// The left-most comment immediately before [token] that is not on the same
/// line as the first non-comment token before it. Returns [token] if there is
/// no such comment.
Token _leadingComment(LineInfo lineInfo, Token token) {
  final previous = token.previous;
  if (previous == null || previous.isEof) {
    return token.precedingComments ?? token;
  }
  Token? comment = token.precedingComments;
  if (!lineInfo.onSameLine(token.offset, previous.offset)) {
    while (comment != null) {
      if (!lineInfo.onSameLine(previous.offset, comment.offset)) break;
      comment = comment.next;
    }
  }
  return comment ?? token;
}

/// The trailing comment following [token] if it sits on the same line, else
/// [token] itself. Declarations never carry a trailing comma, so the analysis
/// server's comma handling is not needed here.
Token _trailingComment(LineInfo lineInfo, Token token) {
  final next = token.next;
  if (next == null) return token;
  Token? comment = next.precedingComments;
  if (comment != null && lineInfo.onSameLine(comment.offset, token.offset)) {
    var following = comment.next;
    while (following != null &&
        lineInfo.onSameLine(following.offset, token.offset)) {
      comment = following;
      following = following.next;
    }
    return comment!;
  }
  return token;
}

/// Half-open character range `[offset, end)` of a node including its comments.
typedef NodeRange = ({int offset, int end});
