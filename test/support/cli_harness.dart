/// Runs the real CLI as a subprocess against a throwaway project.
///
/// The tool's public surface is `bin/dart_modernize.dart`, so the tests go
/// through it instead of calling into `lib/src`. [runCli] writes a pubspec and
/// the given files into a temp directory, runs the binary over it, and returns
/// the exit code, the output, and a way to read the files back.
///
/// Tests check what the tool leaves on disk and what it prints, never private
/// methods.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Every feature folder name, in the order the pipeline documents.
const allFeatures = <String>[
  'dot_shorthands',
  'private_named_parameters',
  'primary_constructors',
  'super_parameters',
  'switch_expressions',
  'cascades',
  'inline_return',
  'final_locals',
  'prefer_inferred_types',
  'expression_bodies',
  'string_interpolation',
  'null_aware_spread',
  'null_aware_elements',
  'null_aware_conditionals',
  'destructure_for_in',
  'destructure_locals',
  'collection_elements',
  'organize_imports',
  'sort_members',
  'sort_constructors_first',
  'fix_all',
  'abstract_final_classes',
];

/// A minimal, dependency-free pubspec that satisfies the tool's validator and
/// lets the analyzer resolve SDK (`dart:`) types without a `pub get`.
const defaultPubspec = '''
name: fixture_project
environment:
  sdk: ">=3.13.0 <4.0.0"
''';

/// Passes that are off by default, by fixture-folder name.
///
/// Mirrors `defaultOffTransformations` in `lib/src/cli/options.dart`.
const defaultOffFeatures = <String>{'sort_members', 'collection_elements'};

/// Fixture-folder name to CLI flag name. One entry per pass, so wiring up a new
/// one is a single line here.
const featureFlags = <String, String>{
  'dot_shorthands': 'dot-shorthands',
  'private_named_parameters': 'private-named-parameters',
  'primary_constructors': 'primary-constructors',
  'super_parameters': 'super-parameters',
  'switch_expressions': 'switch-expressions',
  'cascades': 'cascades',
  'inline_return': 'inline-return',
  'final_locals': 'final-locals',
  'prefer_inferred_types': 'prefer-inferred-types',
  'expression_bodies': 'expression-bodies',
  'string_interpolation': 'string-interpolation',
  'null_aware_spread': 'null-aware-spread',
  'null_aware_elements': 'null-aware-elements',
  'null_aware_conditionals': 'null-aware-conditionals',
  'destructure_for_in': 'destructure-for-in',
  'destructure_locals': 'destructure-locals',
  'collection_elements': 'collection-elements',
  'organize_imports': 'organize-imports',
  'sort_members': 'sort-members',
  'sort_constructors_first': 'sort-constructors-first',
  'fix_all': 'fix-all',
  'abstract_final_classes': 'abstract-final-classes',
};

/// Path to the CLI entry point, relative to [_packageRoot].
const _binPath = 'bin/dart_modernize.dart';

/// Absolute path to the package under test (the `dart test` working directory).
final String _packageRoot = Directory.current.absolute.path;

/// Creates a throwaway project holding [files], keyed by path relative to the
/// project root.
///
/// The directory is deleted on tear-down, so call this from a test or `setUp`.
/// Pair it with [invokeCli] when a test runs the CLI more than once on the same
/// project; for a single run, [runCli] does both.
Directory createProject({
  required Map<String, String> files,
  String pubspec = defaultPubspec,
}) {
  final project = Directory.systemTemp.createTempSync('dm_test_');
  addTearDown(() {
    if (project.existsSync()) project.deleteSync(recursive: true);
  });

  File(p.join(project.path, 'pubspec.yaml')).writeAsStringSync(pubspec);
  files.forEach((relativePath, contents) {
    final file = File(p.join(project.path, relativePath));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(contents);
  });

  return project;
}

/// Runs the CLI once against [project]. The project path is appended to [args].
///
/// Adds `--no-verify` unless the caller passes one of the verify flags itself.
/// Verification runs `dart analyze` twice more per run, which would roughly
/// double an already subprocess-heavy suite, and `verify_test.dart` covers it
/// properly on its own.
Future<CliResult> invokeCli(
  Directory project, {
  List<String> args = const [],
}) async {
  final hasVerifyFlag = args.any((a) => a == '--verify' || a == '--no-verify');
  final effectiveArgs = hasVerifyFlag ? args : ['--no-verify', ...args];
  final result = await Process.run(
    Platform.resolvedExecutable, // the `dart` binary running these tests
    ['run', _binPath, ...effectiveArgs, project.path],
    workingDirectory: _packageRoot,
    stdoutEncoding: systemEncoding,
    stderrEncoding: systemEncoding,
  );

  return .new(
    project: project,
    exitCode: result.exitCode,
    stdout: result.stdout as String,
    stderr: result.stderr as String,
  );
}

/// Arguments that run only [feature], e.g. `['--only', 'dot-shorthands']`.
List<String> onlyFeatureArgs(String feature) => onlyFeaturesArgs({feature});

/// Arguments that run only [features], as one comma-separated `--only` flag.
///
/// Unknown names are dropped rather than throwing, so pass literals from
/// [allFeatures]. An empty set emits no flag at all, which leaves every pass on
/// rather than off.
List<String> onlyFeaturesArgs(Set<String> features) {
  final names = [for (final feature in features) ?featureFlags[feature]];
  return names.isEmpty ? const [] : ['--only', names.join(',')];
}

/// Creates a throwaway project and runs the CLI against it, in one call.
Future<CliResult> runCli({
  required Map<String, String> files,
  List<String> args = const [],
  String pubspec = defaultPubspec,
}) {
  final project = createProject(files: files, pubspec: pubspec);
  return invokeCli(project, args: args);
}

/// The flag that switches an off-by-default [feature] on, or nothing when it
/// already runs by default.
List<String> enableFeatureArgs(String feature) =>
    defaultOffFeatures.contains(feature)
    ? ['--${featureFlags[feature]}']
    : const [];

/// The flag that turns [feature] off, or nothing when it is off by default
/// anyway.
List<String> withoutFeatureArgs(String feature) =>
    defaultOffFeatures.contains(feature)
    ? const []
    : ['--no-${featureFlags[feature]}'];

/// The outcome of a single CLI invocation against a throwaway project.
final class CliResult {
  CliResult({
    required this.project,
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  /// Root directory of the throwaway project the tool ran against.
  final Directory project;

  /// Process exit code (`0` on success).
  final int exitCode;

  /// Captured standard output.
  final String stdout;

  /// Captured standard error.
  final String stderr;

  /// Whether a file relative to the project root exists.
  bool exists(String relativePath) =>
      File(p.join(project.path, relativePath)).existsSync();

  /// Reads a file back, as UTF-8. That drops any BOM, so use [readBytes] when a
  /// test cares about the BOM or the exact line endings.
  String read(String relativePath) =>
      File(p.join(project.path, relativePath)).readAsStringSync();

  /// Reads a file back as raw bytes, BOM and line endings included.
  List<int> readBytes(String relativePath) =>
      File(p.join(project.path, relativePath)).readAsBytesSync();
}
