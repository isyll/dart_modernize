/// Moves constructor declarations before all other class members.
///
/// Satisfies the `sort_constructors_first` lint: every constructor appears
/// before any non-constructor member in a class, mixin, enum, extension, or
/// extension-type body. The body of a primary constructor (`this : ...;`)
/// counts as a constructor.
///
/// A body with a `// ignore: sort_constructors_first` comment, or a file with
/// `// ignore_for_file: sort_constructors_first`, is left as written: the
/// author kept that order on purpose, and moving the constructors would leave
/// the comment pointing at nothing.
library;

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/source/line_info.dart';

import 'edit_diff.dart';
import 'node_range.dart';
import 'source_edit.dart';

/// Returns the edits that move all constructors before other class members in
/// [unit], or an empty list when every body already has constructors first.
List<SourceEdit> sortConstructorsFirstEdits(
  String content,
  CompilationUnit unit,
  LineInfo lineInfo,
) {
  final newCode = _ConstructorSorter(content, unit, lineInfo).run();
  if (newCode == null) return const [];
  final edit = computeSimpleDiff(content, newCode);
  return edit == null ? const [] : [edit];
}

class _ConstructorSorter {
  _ConstructorSorter(this._initial, this._unit, this._lineInfo)
    : _code = _initial;
  final String _initial;
  final CompilationUnit _unit;
  final LineInfo _lineInfo;

  String _code;

  static final _ignoreForFile = RegExp(
    r'//\s*ignore_for_file:[^\n]*\bsort_constructors_first\b',
  );
  static final _ignoreLine = RegExp(
    r'//\s*ignore:[^\n]*\bsort_constructors_first\b',
  );

  String? run() {
    if (_ignoreForFile.hasMatch(_initial)) return null;
    for (final node in _unit.declarations) {
      final members = switch (node) {
        ClassDeclaration(:final body) => body.members,
        EnumDeclaration(:final body) => body.members,
        ExtensionDeclaration(:final body) => body.members,
        ExtensionTypeDeclaration(:final body) => body.members,
        MixinDeclaration(:final body) => body.members,
        _ => null,
      };
      if (members == null) continue;
      if (_ignoreLine.hasMatch(_initial.substring(node.offset, node.end))) {
        continue;
      }
      _processBody(members);
    }
    return _code == _initial ? null : _code;
  }

  static bool _isConstructor(ClassMember member) =>
      member is ConstructorDeclaration || member is PrimaryConstructorBody;

  void _processBody(List<ClassMember> members) {
    // Fast path: only reorder if some constructor follows a non-constructor.
    var seenNonConstructor = false;
    var needsSort = false;
    for (final m in members) {
      if (_isConstructor(m)) {
        if (seenNonConstructor) {
          needsSort = true;
          break;
        }
      } else {
        seenNonConstructor = true;
      }
    }
    if (!needsSort) return;

    // Capture each member's text range and verbatim content.
    final entries = <_Entry>[];
    for (final m in members) {
      final range = nodeWithComments(_lineInfo, m);
      entries.add(
        .new(
          isConstructor: _isConstructor(m),
          offset: range.offset,
          end: range.end,
          text: _code.substring(range.offset, range.end),
        ),
      );
    }

    // New order: all constructors first (original relative order preserved),
    // then all other members (original relative order preserved).
    final sorted = [
      ...entries.where((e) => e.isConstructor),
      ...entries.where((e) => !e.isConstructor),
    ];

    // Apply text swaps from highest offset downward so that each replacement
    // leaves the offsets of earlier (lower-offset) entries valid.
    //
    // Swapping only member texts keeps the gaps (blank lines and indentation)
    // between slots in their original positions; `dart format` normalises the
    // spacing afterward. Because swapping preserves the total byte count of
    // every class body, the absolute offsets of later top-level declarations
    // remain accurate when this class is not the last one in the file.
    for (var i = entries.length - 1; i >= 0; i--) {
      final newEntry = sorted[i];
      final oldEntry = entries[i];
      if (!identical(newEntry, oldEntry)) {
        _code =
            _code.substring(0, oldEntry.offset) +
            newEntry.text +
            _code.substring(oldEntry.end);
      }
    }
  }
}

final class _Entry({
  required final bool isConstructor,
  required final int offset,
  required final int end,
  required final String text,
});
