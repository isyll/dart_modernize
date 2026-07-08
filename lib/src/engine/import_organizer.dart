/// Sorts, groups, deduplicates, and prunes import/export/part directives.
///
/// Directives are split into groups (`dart:`, `package:`, other URI schemes,
/// then relative paths), sorted within each group, and separated by a blank
/// line. When [removeUnused] is set, unused, duplicate, and redundant imports
/// are removed, along with unused names in `show` clauses, using the diagnostics
/// from the resolved unit.
///
/// A file header (the leading doc comment when there is no `library` directive)
/// stays at the top instead of moving with the first import.
library;

import 'dart:math' as math;

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:analyzer/source/line_info.dart';

import 'edit_diff.dart';
import 'source_edit.dart';

/// Diagnostic code names that mark an import as safe to remove.
const _unusedImportCodes = {
  'duplicate_import',
  'unused_import',
  'unnecessary_import',
};

/// Returns the edits that organize the directives of [unit], or an empty list
/// when they are already organized.
List<SourceEdit> organizeImportEdits(
  String content,
  CompilationUnit unit,
  LineInfo lineInfo,
  List<Diagnostic> diagnostics, {
  bool removeUnused = true,
}) {
  final newCode = _ImportOrganizer(
    content,
    unit,
    lineInfo,
    diagnostics,
    removeUnused: removeUnused,
  ).run();
  if (newCode == null) return const [];
  final edit = computeSimpleDiff(content, newCode);
  return edit == null ? const [] : [edit];
}

/// Orders two directive URIs: scheme first, then path.
int _compareDirectiveUri(String a, String b) {
  if (!a.startsWith('package:') || !b.startsWith('package:')) {
    if (!a.startsWith('/') && !b.startsWith('/')) {
      return a.compareTo(b);
    }
  }
  final indexA = a.indexOf('/');
  final indexB = b.indexOf('/');
  if (indexA == -1 || indexB == -1) return a.compareTo(b);
  final result = a.substring(0, indexA).compareTo(b.substring(0, indexB));
  if (result != 0) return result;
  return a.substring(indexA + 1).compareTo(b.substring(indexB + 1));
}

/// Picks the group for a directive with the given [uri] and [kind].
_DirectiveGroup _groupOf(String uri, _DirectiveSortKind kind) {
  switch (kind) {
    case .import:
      if (uri.startsWith('dart:')) return .importSdk;
      if (uri.startsWith('package:')) return .importPkg;
      if (uri.contains('://')) return .importOther;
      return .importRel;
    case .export:
      if (uri.startsWith('dart:')) return .exportSdk;
      if (uri.startsWith('package:')) return .exportPkg;
      if (uri.contains('://')) return .exportOther;
      return .exportRel;
    case .part:
      return .part;
  }
}

/// The groups directives are sorted into, in order. Directives in the same
/// group are kept together and separated from the next group by a blank line.
enum _DirectiveGroup {
  importSdk,
  importPkg,
  importOther,
  importRel,
  exportSdk,
  exportPkg,
  exportOther,
  exportRel,
  part,
}

class _DirectiveInfo implements Comparable<_DirectiveInfo> {
  _DirectiveInfo(
    this.directive,
    this.priority,
    this.uri,
    this.offset,
    this.end,
    this.text,
  );
  final UriBasedDirective directive;
  final _DirectiveGroup priority;
  final String uri;
  final int offset;
  final int end;

  final String text;

  @override
  int compareTo(_DirectiveInfo other) {
    if (priority == other.priority) {
      final compare = _compareDirectiveUri(uri, other.uri);
      if (compare != 0) return compare;
      return text.compareTo(other.text);
    }
    return priority.index - other.priority.index;
  }
}

enum _DirectiveSortKind { import, export, part }

class _ImportOrganizer {
  _ImportOrganizer(
    this._initialCode,
    this._unit,
    this._lineInfo,
    this._diagnostics, {
    this.removeUnused = true,
  }) : code = _initialCode {
    endOfLine = code.contains('\r\n') ? '\r\n' : '\n';
    hasUnresolvedIdentifierError = _diagnostics.any(
      (d) => d.diagnosticCode.isUnresolvedIdentifier,
    );
  }
  static final _ignoreMatcher = RegExp(r'//+[ ]*ignore:');
  final String _initialCode;
  final CompilationUnit _unit;
  final LineInfo _lineInfo;

  final List<Diagnostic> _diagnostics;
  final bool removeUnused;
  String code;

  String endOfLine = '\n';

  bool hasUnresolvedIdentifierError = false;

  String? run() {
    _organizeDirectives();
    return code == _initialCode ? null : code;
  }

  /// The leading comment for [beginToken], or null if none should travel with
  /// the directive (e.g. a file header comment that must stay at the top).
  Token? _getLeadingComment(
    Token beginToken, {
    required bool isPseudoLibraryDirective,
  }) {
    if (beginToken.precedingComments == null) return null;

    Token? firstComment = beginToken.precedingComments;
    var comment = firstComment;
    var nextComment = comment?.next;
    while (isPseudoLibraryDirective && comment != null && nextComment != null) {
      if (_lineInfo.lineNumberDifference(comment.offset, nextComment.offset) >
          1) {
        firstComment = nextComment;
      }
      comment = nextComment;
      nextComment = comment.next;
    }

    if (firstComment is LanguageVersionToken) {
      firstComment = firstComment.next;
    }

    if (firstComment != null &&
        firstComment == _unit.beginToken.precedingComments) {
      return _isIgnoreComment(firstComment) ? firstComment : null;
    }

    comment = firstComment;
    if (isPseudoLibraryDirective && comment != null) {
      return _lineInfo.lineNumberDifference(
                beginToken.offset,
                comment.offset,
              ) ==
              -1
          ? comment
          : null;
    }
    while (comment != null &&
        _lineInfo.onSameLine(beginToken.previous!.end, comment.offset)) {
      comment = comment.next;
    }
    return comment;
  }

  /// The trailing comment on the same line as [directive], or null.
  Token? _getTrailingComment(UriBasedDirective directive) {
    Token? comment = directive.endToken.next!.precedingComments;
    while (comment != null) {
      if (_lineInfo.onSameLine(comment.offset, directive.end)) return comment;
      comment = comment.next;
    }
    return null;
  }

  bool _isUnusedImport(UriBasedDirective directive) {
    for (final diagnostic in _diagnostics) {
      if (_unusedImportCodes.contains(
            diagnostic.diagnosticCode.lowerCaseName,
          ) &&
          directive.uri.offset == diagnostic.offset) {
        return true;
      }
    }
    return false;
  }

  bool _isUnusedShowName(SimpleIdentifier name) {
    for (final diagnostic in _diagnostics) {
      if (diagnostic.diagnosticCode.lowerCaseName == 'unused_shown_name' &&
          name.offset == diagnostic.offset) {
        return true;
      }
    }
    return false;
  }

  void _organizeDirectives() {
    final hasLibraryDirective = _unit.directives.any(
      (d) => d is LibraryDirective,
    );
    final directives = <_DirectiveInfo>[];
    for (final directive in _unit.directives) {
      if (directive is! UriBasedDirective) continue;
      final _DirectiveSortKind kind;
      if (directive is ImportDirective) {
        kind = .import;
      } else if (directive is ExportDirective) {
        kind = .export;
      } else if (directive is PartDirective) {
        kind = .part;
      } else {
        continue;
      }
      final uriContent = directive.uri.stringValue ?? '';
      final priority = _groupOf(uriContent, kind);

      var offset = directive.offset;
      var end = directive.end;

      final isPseudoLibraryDirective =
          !hasLibraryDirective && directive == _unit.directives.first;
      int? libraryDocsAndAnnotationsEndOffset;
      if (isPseudoLibraryDirective) {
        // The analyzer doesn't expose annotation target kinds, so only a
        // leading doc comment is treated as belonging to the file.
        libraryDocsAndAnnotationsEndOffset =
            directive.documentationComment?.end;
        if (libraryDocsAndAnnotationsEndOffset != null) {
          libraryDocsAndAnnotationsEndOffset = _lineInfo.getOffsetOfLineAfter(
            libraryDocsAndAnnotationsEndOffset,
          );
          final nextLineOffset = _lineInfo.getOffsetOfLineAfter(
            libraryDocsAndAnnotationsEndOffset,
          );
          if (code
              .substring(libraryDocsAndAnnotationsEndOffset, nextLineOffset)
              .trim()
              .isEmpty) {
            libraryDocsAndAnnotationsEndOffset = nextLineOffset;
          }
        }
      }

      final leadingComment = _getLeadingComment(
        directive.beginToken,
        isPseudoLibraryDirective: isPseudoLibraryDirective,
      );
      final trailingComment = _getTrailingComment(directive);

      if (leadingComment != null) {
        offset = libraryDocsAndAnnotationsEndOffset != null
            ? math.max(
                libraryDocsAndAnnotationsEndOffset,
                leadingComment.offset,
              )
            : leadingComment.offset;
      }
      if (trailingComment != null) {
        end = trailingComment.end;
      }
      offset = libraryDocsAndAnnotationsEndOffset ?? offset;
      final text = code.substring(offset, end);
      directives.add(.new(directive, priority, uriContent, offset, end, text));
    }
    if (directives.isEmpty) return;

    final firstDirectiveOffset = directives.first.offset;
    final lastDirectiveEnd = directives.last.end;

    directives.sort();

    final sb = StringBuffer();
    _DirectiveGroup? currentPriority;
    var previousDirectiveText = '';
    final showCombinators = <ImportDirective, List<SimpleIdentifier>>{};
    for (final directiveInfo in directives) {
      if (!hasUnresolvedIdentifierError) {
        final directive = directiveInfo.directive;
        if (removeUnused && _isUnusedImport(directive) ||
            (removeUnused && previousDirectiveText == directiveInfo.text)) {
          continue;
        }
        if (directive is ImportDirective && directive.combinators.isNotEmpty) {
          final shownNames = directive.combinators
              .whereType<ShowCombinator>()
              .map((combinator) => combinator.shownNames)
              .expand((names) => names);
          showCombinators[directive] = shownNames
              .where(_isUnusedShowName)
              .toList();
        }
      }
      if (currentPriority != directiveInfo.priority) {
        if (currentPriority != null) sb.write(endOfLine);
        currentPriority = directiveInfo.priority;
      }
      var text = directiveInfo.text;
      final unusedShown = showCombinators[directiveInfo.directive];
      if (unusedShown != null) {
        final showOffset = text.indexOf('show');
        for (final name in unusedShown) {
          if (text.contains('${name.name},')) {
            text = text.replaceFirst('${name.name}, ', '', showOffset);
          } else if (text.contains(', ${name.name}')) {
            text = text.replaceFirst(', ${name.name}', '', showOffset);
          }
        }
      }
      sb.write(text);
      sb.write(endOfLine);
      previousDirectiveText = text;
    }
    final directivesCode = sb.toString().trimRight();

    code =
        code.substring(0, firstDirectiveOffset) +
        directivesCode +
        code.substring(lastDirectiveEnd);
  }

  static bool _isIgnoreComment(Token token) =>
      _ignoreMatcher.matchAsPrefix(token.lexeme) != null;
}
