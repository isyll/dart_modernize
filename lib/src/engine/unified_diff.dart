/// Produces a readable unified diff between two versions of a file's text.
///
/// Used by the dry-run output so a preview shows exactly which lines a
/// transformation would add or remove, without writing anything to disk.
library;

/// Renders the line-level changes from [before] to [after] as a unified diff.
///
/// [beforeLabel] and [afterLabel] are the names shown on the `---`/`+++`
/// header lines (e.g. `a/lib/main.dart` and `b/lib/main.dart`). [context] is
/// the number of unchanged lines kept around each change.
///
/// Returns just the two header lines when the inputs are identical.
String unifiedDiff(
  String beforeLabel,
  String afterLabel,
  String before,
  String after, {
  int context = 3,
}) {
  final beforeLines = before.split('\n');
  final afterLines = after.split('\n');
  final ops = _diff(beforeLines, afterLines);

  final buffer = StringBuffer()
    ..writeln('--- $beforeLabel')
    ..writeln('+++ $afterLabel');

  // Line numbers (0-based) within each side, paired to each op.
  final beforeLineOf = <int>[];
  final afterLineOf = <int>[];
  var beforeCursor = 0;
  var afterCursor = 0;
  for (final op in ops) {
    switch (op.kind) {
      case .equal:
        beforeLineOf.add(beforeCursor++);
        afterLineOf.add(afterCursor++);
      case .remove:
        beforeLineOf.add(beforeCursor++);
        afterLineOf.add(-1);
      case .add:
        beforeLineOf.add(-1);
        afterLineOf.add(afterCursor++);
    }
  }

  final changed = [
    for (var i = 0; i < ops.length; i++)
      if (ops[i].kind != .equal) i,
  ];
  if (changed.isEmpty) return buffer.toString();

  // Expand each change by [context] lines, merging groups that touch.
  final hunks = <List<int>>[];
  var start = _clamp(changed.first - context, ops.length - 1);
  var end = _clamp(changed.first + context, ops.length - 1);
  for (final index in changed.skip(1)) {
    final nextStart = _clamp(index - context, ops.length - 1);
    if (nextStart <= end + 1) {
      end = _clamp(index + context, ops.length - 1);
    } else {
      hunks.add([start, end]);
      start = nextStart;
      end = _clamp(index + context, ops.length - 1);
    }
  }
  hunks.add([start, end]);

  for (final hunk in hunks) {
    final from = hunk[0];
    final to = hunk[1];

    var beforeStart = -1;
    var afterStart = -1;
    var beforeCount = 0;
    var afterCount = 0;
    for (var i = from; i <= to; i++) {
      if (beforeLineOf[i] >= 0) {
        if (beforeStart < 0) beforeStart = beforeLineOf[i];
        beforeCount++;
      }
      if (afterLineOf[i] >= 0) {
        if (afterStart < 0) afterStart = afterLineOf[i];
        afterCount++;
      }
    }
    if (beforeStart < 0) beforeStart = 0;
    if (afterStart < 0) afterStart = 0;

    buffer.writeln(
      '@@ -${beforeStart + 1},$beforeCount '
      '+${afterStart + 1},$afterCount @@',
    );
    for (var i = from; i <= to; i++) {
      final op = ops[i];
      final prefix = switch (op.kind) {
        .equal => ' ',
        .remove => '-',
        .add => '+',
      };
      buffer.writeln('$prefix${op.text}');
    }
  }

  return buffer.toString();
}

int _clamp(int value, int max) => value < 0
    ? 0
    : value > max
    ? max
    : value;

/// Classic longest-common-subsequence line diff.
List<_Op> _diff(List<String> before, List<String> after) {
  final n = before.length;
  final m = after.length;

  final lengths = List.generate(
    n + 1,
    (_) => List<int>.filled(m + 1, 0),
    growable: false,
  );
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      lengths[i][j] = before[i] == after[j]
          ? lengths[i + 1][j + 1] + 1
          : (lengths[i + 1][j] >= lengths[i][j + 1]
                ? lengths[i + 1][j]
                : lengths[i][j + 1]);
    }
  }

  final ops = <_Op>[];
  var i = 0;
  var j = 0;
  while (i < n && j < m) {
    if (before[i] == after[j]) {
      ops.add(.new(.equal, before[i]));
      i++;
      j++;
    } else if (lengths[i + 1][j] >= lengths[i][j + 1]) {
      ops.add(.new(.remove, before[i]));
      i++;
    } else {
      ops.add(.new(.add, after[j]));
      j++;
    }
  }
  while (i < n) {
    ops.add(.new(.remove, before[i]));
    i++;
  }
  while (j < m) {
    ops.add(.new(.add, after[j]));
    j++;
  }
  return ops;
}

enum _Kind { equal, remove, add }

class _Op {
  final _Kind kind;
  final String text;
  const _Op(this.kind, this.text);
}
