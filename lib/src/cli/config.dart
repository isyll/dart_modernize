import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Project configuration read from the `dart_modernize:` section of
/// `analysis_options.yaml`.
///
/// Lets a project record which passes to switch on or off, how to tune them,
/// and which extra paths to skip, so those settings live in the repo instead of
/// being repeated on every command line. CLI flags win over this file; the
/// layering is resolved in `CliOptions.fromResults`.
///
/// ```yaml
/// dart_modernize:
///   enabled:
///     - sort-members
///   disabled:
///     - organize-imports
///     - format
///   exclude:
///     - lib/generated/**
///   line_length: 120
///   options:
///     dot-shorthands:
///       constructors: false
///   lint_fixes:
///     - unnecessary_underscores
/// ```
final class DartModernizeConfig {
  const DartModernizeConfig({
    this.enabled = const <String>{},
    this.disabled = const <String>{},
    this.excludes = const <String>[],
    this.lineLength,
    this.passOptions = const <String, Map<String, Object?>>{},
    this.lintFixes = const <String>[],
  });

  const DartModernizeConfig.empty()
    : enabled = const <String>{},
      disabled = const <String>{},
      excludes = const <String>[],
      lineLength = null,
      passOptions = const <String, Map<String, Object?>>{},
      lintFixes = const <String>[];

  /// Pass names to switch on, e.g. an off-by-default pass such as sort-members.
  final Set<String> enabled;

  /// Pass names to switch off. `format` turns off the final `dart format`.
  final Set<String> disabled;

  /// Extra exclude globs, added on top of `analyzer: exclude:` and `--exclude`.
  final List<String> excludes;

  /// Page width handed to `dart format`, or null to let it decide.
  final int? lineLength;

  /// Per-pass settings, pass name to setting name to value. Validated against
  /// `passSettings` in `CliOptions.fromResults`.
  final Map<String, Map<String, Object?>> passOptions;

  /// Lint names whose `dart fix` corrections are applied even when the
  /// project does not enable the lint.
  final List<String> lintFixes;

  bool get isEmpty =>
      enabled.isEmpty &&
      disabled.isEmpty &&
      excludes.isEmpty &&
      lineLength == null &&
      passOptions.isEmpty &&
      lintFixes.isEmpty;
}

/// Reads the `dart_modernize:` section from
/// [projectPath]/`analysis_options.yaml`.
///
/// Returns an empty config when the file, or the section, is absent. Pass names
/// are not validated here; `CliOptions.fromResults` checks them against
/// `transformationNames` so a typo fails with the full list.
DartModernizeConfig readDartModernizeConfig(String projectPath) {
  final file = File(p.join(projectPath, 'analysis_options.yaml'));
  if (!file.existsSync()) return const .empty();

  final dynamic yaml = loadYaml(file.readAsStringSync());
  if (yaml is! YamlMap) return const .empty();
  final dynamic section = yaml['dart_modernize'];
  if (section is! YamlMap) return const .empty();

  final dynamic lineLength = section['line_length'];
  if (lineLength != null && (lineLength is! int || lineLength <= 0)) {
    throw const FormatException(
      'analysis_options.yaml dart_modernize: line_length must be a positive '
      'integer.',
    );
  }

  return .new(
    enabled: _stringSet(section['enabled']),
    disabled: _stringSet(section['disabled']),
    excludes: _stringList(section['exclude']),
    lineLength: lineLength as int?,
    passOptions: _passOptions(section['options']),
    lintFixes: _stringList(section['lint_fixes']),
  );
}

Map<String, Map<String, Object?>> _passOptions(dynamic node) {
  if (node == null) return const {};
  if (node is! YamlMap) {
    throw const FormatException(
      'analysis_options.yaml dart_modernize: options must map pass names to '
      'their settings.',
    );
  }
  return {
    for (final MapEntry(:key, :value) in node.entries)
      '$key': switch (value) {
        YamlMap() => {
          for (final setting in value.entries) '${setting.key}': setting.value,
        },
        _ => throw FormatException(
          'analysis_options.yaml dart_modernize: options for "$key" must be a '
          'map of settings.',
        ),
      },
  };
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
