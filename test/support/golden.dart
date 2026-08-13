/// Reusable golden-test runner for the transformation pipeline.
///
/// A *golden test* pins the exact output of a transformation for a given input.
/// Cases live under `test/fixtures/<feature>/` and come in two shapes:
///
///   * **A pair**: `<case>.input.dart` plus `<case>.expected.dart`.
///     The tool is run over the input and the result must equal the expected
///     file, byte for byte. Both carry the `.dart` extension so an editor reads
///     them as the Dart they are. Nothing in the toolchain rewrites them out
///     from under the suite: `analysis_options.yaml` excludes `test/fixtures/**`
///     from the analyzer, and CI formats only `git ls-files '*.dart'
///     ':!test/fixtures'`. That exclusion is what keeps a fixture free to hold
///     deliberately non-idiomatic input, and output the tool has already
///     formatted its own way.
///
///   * **A negative case**: a single `<case>.unchanged.dart`.
///     The transformation must *not* apply, so the expected output is the input
///     itself. One file documents intent ("this should stay as-is") with no
///     duplicated content to drift out of sync.
///
/// Adding a case is therefore just adding one or two files; no Dart code.
///
/// All of a feature's input files are dropped into a single throwaway package
/// and the real CLI is run **once** with only that feature's pass enabled (see
/// [onlyFeatureArgs]). Each case then becomes its own `test()` so a failure
/// names the exact fixture that regressed. Because every case is a separate
/// library file with no cross-imports, top-level names may safely repeat across
/// cases.
///
/// Optionally, a feature folder may contain a `pubspec.yaml` and/or
/// `analysis_options.yaml`; when present they replace/augment the defaults for
/// that feature's project (e.g. primary constructors need a higher SDK; import
/// and lint fixes may need specific lints enabled).
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'cli_harness.dart';

/// Absolute path to `test/fixtures`, resolved from the package root.
final String _fixturesRoot = p.join(
  Directory.current.absolute.path,
  'test',
  'fixtures',
);

/// Defines a complete golden-test group for [feature].
///
/// Call once per feature from a `_test.dart` file. It discovers the cases,
/// runs the CLI a single time with only [feature] enabled, and emits one
/// assertion per case.
void defineGoldenSuite(String feature) {
  group('golden: $feature', () {
    final cases = discoverCases(feature);

    test(
      'has at least one fixture case',
      () => expect(
        cases,
        isNotEmpty,
        reason:
            'No fixtures found in test/fixtures/$feature/. Add a '
            '<case>.input.dart + <case>.expected pair, or a '
            '<case>.unchanged.dart negative case.',
      ),
    );

    if (cases.isEmpty) return;

    late CliResult result;

    setUpAll(() async {
      final pubspec = _featureFile(feature, 'pubspec.yaml');
      final analysisOptions = _featureFile(feature, 'analysis_options.yaml');
      result = await runCli(
        files: {
          for (final c in cases) c.projectFile: c.input,
          ..._supportFiles(feature),
          'analysis_options.yaml': ?analysisOptions,
        },
        args: onlyFeatureArgs(feature),
        pubspec: pubspec ?? defaultPubspec,
      );
    });

    for (final c in cases) {
      final label = c.isNegative ? '${c.name} (must not change)' : c.name;
      test(
        label,
        () => expect(
          result.read(c.projectFile),
          c.expected,
          reason: c.isNegative
              ? 'Negative case "${c.name}": the transformation fired but the '
                    'context does not support it; output must equal input.'
              : 'Golden case "${c.name}" did not match '
                    'test/fixtures/$feature/${c.name}.expected.',
        ),
      );
    }
  });
}

/// Discovers every golden case under `test/fixtures/[feature]/`.
///
/// Returns them sorted by name for deterministic test ordering.
List<GoldenCase> discoverCases(String feature) {
  final dir = Directory(p.join(_fixturesRoot, feature));
  if (!dir.existsSync()) return const [];

  final cases = <GoldenCase>[];
  for (final entity in dir.listSync()) {
    if (entity is! File) continue;
    final fileName = p.basename(entity.path);

    if (fileName.endsWith('.input.dart')) {
      final stem = fileName.substring(
        0,
        fileName.length - '.input.dart'.length,
      );
      final expectedFile = File(p.join(dir.path, '$stem.expected.dart'));
      if (!expectedFile.existsSync()) {
        throw StateError(
          'Golden case "$stem" in $feature is missing $stem.expected.dart. '
          'Every *.input.dart needs a matching *.expected.dart file.',
        );
      }
      cases.add(
        .new(
          name: stem,
          projectFile: 'lib/$stem.dart',
          input: entity.readAsStringSync(),
          expected: expectedFile.readAsStringSync(),
          isNegative: false,
        ),
      );
    } else if (fileName.endsWith('.unchanged.dart')) {
      final stem = fileName.substring(
        0,
        fileName.length - '.unchanged.dart'.length,
      );
      final content = entity.readAsStringSync();
      cases.add(
        .new(
          name: stem,
          projectFile: 'lib/$stem.dart',
          input: content,
          expected: content,
          isNegative: true,
        ),
      );
    }
  }

  cases.sort((a, b) => a.name.compareTo(b.name));
  return cases;
}

/// Reads an optional per-feature override file (`pubspec.yaml`,
/// `analysis_options.yaml`) from the feature folder, or returns null.
String? _featureFile(String feature, String name) {
  final file = File(p.join(_fixturesRoot, feature, name));
  return file.existsSync() ? file.readAsStringSync() : null;
}

/// Collects support files (`<name>.support.dart`) placed under
/// `test/fixtures/<feature>/`. These are copied into the project as
/// `lib/<name>.dart` *verbatim* and are never asserted on. They exist so a case
/// can `import` a sibling library (e.g. to exercise relative-import grouping).
Map<String, String> _supportFiles(String feature) {
  final dir = Directory(p.join(_fixturesRoot, feature));
  if (!dir.existsSync()) return const {};
  final files = <String, String>{};
  for (final entity in dir.listSync()) {
    if (entity is! File) continue;
    final fileName = p.basename(entity.path);
    if (!fileName.endsWith('.support.dart')) continue;
    final stem = fileName.substring(
      0,
      fileName.length - '.support.dart'.length,
    );
    files['lib/$stem.dart'] = entity.readAsStringSync();
  }
  return files;
}

/// One golden case: the file as it lands in the project plus its expected text.
final class GoldenCase {
  GoldenCase({
    required this.name,
    required this.projectFile,
    required this.input,
    required this.expected,
    required this.isNegative,
  });

  /// Human-readable case name (the fixture stem), used as the test description.
  final String name;

  /// Path of the file inside the throwaway project, e.g. `lib/obvious.dart`.
  final String projectFile;

  /// Source written into the project before running the tool.
  final String input;

  /// Source the file must contain after the tool runs.
  final String expected;

  /// True for `*.unchanged.dart` cases where `expected == input`.
  final bool isNegative;
}
