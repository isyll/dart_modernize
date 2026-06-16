import 'package:path/path.dart' as p;

/// Returns true if [filePath] is a generated file that should be skipped.
///
/// Matches common Dart code-generation suffixes and the `build/` output directory.
bool isGeneratedFile(String filePath) {
  final name = p.basename(filePath);
  if (name.endsWith('.g.dart')) return true;
  if (name.endsWith('.freezed.dart')) return true;
  if (name.endsWith('.gen.dart')) return true;
  if (name.endsWith('.gr.dart')) return true;
  if (name.endsWith('.pb.dart')) return true;
  if (name.endsWith('.pbenum.dart')) return true;
  return p.split(filePath).contains('build');
}
