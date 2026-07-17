/// Git working-tree inspection used to refuse running on uncommitted work.
///
/// The tool edits files in place, so running it over a dirty tree tangles its
/// edits with the user's own and there is no clean way to review or undo just
/// the tool's part. These helpers let the pipeline detect that and stop.
library;

import 'dart:convert';
import 'dart:io';

/// Whether [dir] sits inside a Git working tree.
///
/// Returns false when git is not installed or [dir] is not inside a repository,
/// so the caller can simply skip the clean-tree guard in those cases.
bool isInsideWorkTree(String dir) {
  final ProcessResult result;
  try {
    result = Process.runSync('git', [
      'rev-parse',
      '--is-inside-work-tree',
    ], workingDirectory: dir);
  } on ProcessException {
    return false;
  }
  return result.exitCode == 0 && '${result.stdout}'.trim() == 'true';
}

/// Uncommitted changes to tracked files in the work tree containing [dir].
///
/// Each entry is a `git status --porcelain` line. The list is empty when the
/// tree is clean, when git is missing, or when [dir] is not inside a
/// repository. Untracked files (`??`) are ignored: the guard is about tracked
/// work a modernization edit would tangle with, not brand-new files.
List<String> uncommittedTrackedChanges(String dir) {
  if (!isInsideWorkTree(dir)) return const [];
  final ProcessResult result;
  try {
    result = Process.runSync('git', [
      'status',
      '--porcelain',
    ], workingDirectory: dir);
  } on ProcessException {
    return const [];
  }
  if (result.exitCode != 0) return const [];
  return parseTrackedChanges('${result.stdout}');
}

/// Filters `git status --porcelain` [output] to its tracked-change lines,
/// dropping blank lines and untracked (`??`) entries.
List<String> parseTrackedChanges(String output) => [
  for (final line in const LineSplitter().convert(output))
    if (line.isNotEmpty && !line.startsWith('??')) line,
];
