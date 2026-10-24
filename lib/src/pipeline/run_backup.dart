import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Copies of the files a run may rewrite, kept on disk until the run ends.
///
/// The pipeline writes structural edits before `dart fix`, `dart format` and
/// verification. An exception in those steps is handled in memory, but a hard
/// crash (out of memory, a VM fault, a kill) is not, and used to leave files
/// half modified. The copies live under `.dart_tool/dart_modernize/backup/`,
/// which neither the analyzer nor the tool scans, and `--restore` puts them
/// back. A run that ends, however it ends, deletes them.
final class RunBackup(final String projectPath) {
  String get _root =>
      p.join(projectPath, '.dart_tool', 'dart_modernize', 'backup');

  String get _manifest => p.join(_root, 'manifest.json');

  /// Whether an interrupted run left copies behind.
  bool get exists => File(_manifest).existsSync();

  /// Deletes the copies.
  void discard() {
    final dir = Directory(_root);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }

  /// Writes every saved file back over the project and deletes the copies.
  ///
  /// Returns the project-relative paths it rewrote: the files whose content
  /// differed from the copy.
  List<String> restore() {
    final List<Object?> entries;
    try {
      entries = jsonDecode(File(_manifest).readAsStringSync()) as List<Object?>;
    } on FormatException {
      return const [];
    }
    final restored = <String>[];
    for (final entry in entries.whereType<String>()) {
      final copy = File(p.join(_root, 'files', '$entry.bak'));
      if (!copy.existsSync()) continue;
      final target = File(p.join(projectPath, entry));
      final bytes = copy.readAsBytesSync();
      if (target.existsSync() && _same(target.readAsBytesSync(), bytes)) {
        continue;
      }
      target.writeAsBytesSync(bytes);
      restored.add(entry);
    }
    discard();
    return restored;
  }

  /// Saves the current bytes of [files], absolute paths inside the project.
  ///
  /// The manifest is written last, so a crash while copying leaves no backup
  /// that claims to be complete.
  void save(Iterable<String> files) {
    discard();
    final relative = <String>[];
    for (final path in files) {
      final source = File(path);
      if (!source.existsSync()) continue;
      final rel = p.relative(path, from: projectPath);
      final copy = File(p.join(_root, 'files', '$rel.bak'));
      copy.parent.createSync(recursive: true);
      copy.writeAsBytesSync(source.readAsBytesSync());
      relative.add(rel);
    }
    File(_manifest)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(jsonEncode(relative));
  }

  static bool _same(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
