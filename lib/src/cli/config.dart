import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Project configuration read from the `dart_modernize:` section of
/// `analysis_options.yaml`.
///
/// Lets a project record which passes to switch on or off and which extra paths
/// to skip, so those settings live in the repo instead of being repeated on
/// every command line. CLI flags win over this file; the layering is resolved
/// in `CliOptions.fromResults`.
///
/// ```yaml
/// dart_modernize:
///   enabled:
///     - sort-members
///   disabled:
///     - organize-imports
///   exclude:
///     - lib/generated/**
/// ```
final class DartModernizeConfig {
  const DartModernizeConfig({
    this.enabled = const <String>{},
    this.disabled = const <String>{},
    this.excludes = const <String>[],
  });

  const DartModernizeConfig.empty()
    : enabled = const <String>{},
      disabled = const <String>{},
      excludes = const <String>[];

  /// Pass names to switch on, e.g. an off-by-default pass such as sort-members.
  final Set<String> enabled;

  /// Pass names to switch off.
  final Set<String> disabled;

  /// Extra exclude globs, added on top of `analyzer: exclude:` and `--exclude`.
  final List<String> excludes;

  bool get isEmpty => enabled.isEmpty && disabled.isEmpty && excludes.isEmpty;
}

/// Reads the `dart_modernize:` section from
/// [projectPath]/`analysis_options.yaml`.
///
/// Returns an empty config when the file, or the section, is absent. Pass names
/// are not validated here; `CliOptions.fromResults` checks them against
/// `transformationNames` so a typo fails with the full list.
DartModernizeConfig readDartModernizeConfig(String projectPath) {
  final file = File(p.join(projectPath, 'analysis_options.yaml'));
  if (!file.existsSync()) return const DartModernizeConfig.empty();

  final dynamic yaml = loadYaml(file.readAsStringSync());
  if (yaml is! YamlMap) return const DartModernizeConfig.empty();
  final dynamic section = yaml['dart_modernize'];
  if (section is! YamlMap) return const DartModernizeConfig.empty();

  return DartModernizeConfig(
    enabled: _stringSet(section['enabled']),
    disabled: _stringSet(section['disabled']),
    excludes: _stringList(section['exclude']),
  );
}

Set<String> _stringSet(dynamic node) => {
  if (node is YamlList)
    for (final dynamic e in node)
      if (e is String) e,
};

List<String> _stringList(dynamic node) => [
  if (node is YamlList)
    for (final dynamic e in node)
      if (e is String) e,
];
