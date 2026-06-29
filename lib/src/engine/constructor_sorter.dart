/// Moves constructor declarations before all other class members.
///
/// Satisfies the `sort_constructors_first` lint: every constructor appears
/// before any non-constructor member in a class, mixin, enum, extension, or
/// extension-type body.
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
  final String _initial;
  final CompilationUnit _unit;
  final LineInfo _lineInfo;
  String _code;

  _ConstructorSorter(this._initial, this._unit, this._lineInfo)
    : _code = _initial;

  String? run() {
    for (final node in _unit.declarations) {
      if (node is ClassDeclaration) {
        _processBody(node.body.members);
      } else if (node is EnumDeclaration) {
        _processBody(node.body.members);
      } else if (node is ExtensionDeclaration) {
        _processBody(node.body.members);
      } else if (node is ExtensionTypeDeclaration) {
        _processBody(node.body.members);
      } else if (node is MixinDeclaration) {
        _processBody(node.body.members);
      }
    }
    return _code == _initial ? null : _code;
  }

  void _processBody(List<ClassMember> members) {
    // Fast path: only reorder if some constructor follows a non-constructor.
    var seenNonConstructor = false;
    var needsSort = false;
    for (final m in members) {
      if (m is ConstructorDeclaration) {
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
        _Entry(
          isConstructor: m is ConstructorDeclaration,
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

final class _Entry {
  final bool isConstructor;
  final int offset;
  final int end;
  final String text;

  _Entry({
    required this.isConstructor,
    required this.offset,
    required this.end,
    required this.text,
  });
}
