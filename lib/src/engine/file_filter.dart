import 'dart:io';

import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

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

/// Reads the `analyzer: exclude:` list from [projectPath]/analysis_options.yaml.
List<String> readAnalysisOptionsExcludes(String projectPath) {
  final file = File(p.join(projectPath, 'analysis_options.yaml'));
  if (!file.existsSync()) return const [];
  final dynamic yaml = loadYaml(file.readAsStringSync());
  if (yaml is! YamlMap) return const [];
  final dynamic analyzer = yaml['analyzer'];
  if (analyzer is! YamlMap) return const [];
  final dynamic exclude = analyzer['exclude'];
  if (exclude is! YamlList) return const [];
  return [
    for (final dynamic e in exclude)
      if (e is String) e,
  ];
}

/// Decides whether a file should be skipped during modernization.
///
/// Exclusion sources, checked in order:
///   1. Generated-file suffixes and `build/` directory.
///   2. Glob patterns from [projectPath]/analysis_options.yaml `analyzer: exclude:`.
///   3. Ad-hoc CLI `--exclude` glob patterns.
final class FileFilter {
  final String projectPath;
  final List<Glob> _excludeGlobs;

  FileFilter({
    required this.projectPath,
    List<String> excludePatterns = const [],
  }) : _excludeGlobs = [for (final pat in excludePatterns) .new(pat)];

  /// Merges [projectPath]/analysis_options.yaml excludes with [cliExcludes].
  factory FileFilter.forProject(
    String projectPath, {
    List<String> cliExcludes = const [],
  }) => .new(
    projectPath: projectPath,
    excludePatterns: [
      ...readAnalysisOptionsExcludes(projectPath),
      ...cliExcludes,
    ],
  );

  bool shouldSkip(String filePath) {
    if (isGeneratedFile(filePath)) return true;
    final rel = p.relative(filePath, from: projectPath).replaceAll(r'\', '/');
    return _excludeGlobs.any((g) => g.matches(rel));
  }
}
