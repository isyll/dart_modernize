/// Source ranges for declarations that include their attached comments.
///
/// When the member sorter moves a declaration, the comments that belong to it
/// should move too: a `//` comment on the line above, and a trailing comment on
/// the same line. Doc comments and annotations are already part of the node, so
/// they need no special handling.
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

/// The first comment directly above [token]. A comment that shares a line with
/// the preceding code belongs to that line and is skipped. Returns [token] when
/// there is no leading comment.
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

/// The comment on the same line right after [token], or [token] itself if there
/// is none.
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
