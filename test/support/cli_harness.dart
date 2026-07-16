/// Test harness that drives the **real** `dart_modernize` CLI as a subprocess.
///
/// The project's public surface is `bin/dart_modernize.dart` (see AGENTS.md),
/// so every behavioural test exercises that binary rather than reaching into
/// `lib/src`. Each call to [runCli]:
///
///   1. creates a throwaway pub package in the system temp directory,
///   2. writes a `pubspec.yaml` and the caller-supplied source files into it,
///   3. runs `dart run bin/dart_modernize.dart <args> <projectPath>`, and
///   4. returns a [CliResult] exposing the exit code, captured output, and a
///      way to read the (possibly rewritten) files back.
///
/// Assertions are made on **observable behaviour**: the bytes the tool leaves
/// on disk and what it prints, never on private methods. This keeps the test
/// suite a faithful specification of what the tool does, independent of how the
/// transformations are eventually implemented.
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
  sdk: ">=3.12.0 <4.0.0"
''';

/// The machine-readable CLI flag name for each transformation feature.
///
/// Keyed by the *fixture folder* name (snake_case, mirroring
/// `test/fixtures/<feature>/`); the value is the `--<flag>` spelling accepted
/// by the CLI. Keeping the mapping in one place means a new feature is wired up
/// by adding a single entry here.
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

/// Creates a throwaway project containing [files] and a [pubspec].
///
/// [files] maps a path *relative to the project root* (e.g. `'lib/a.dart'`) to
/// its contents. The directory is registered for deletion via [addTearDown], so
/// this must be called from a test body (or `setUp`).
///
/// Use this with [invokeCli] when a test needs to run the CLI more than once
/// against the same project (e.g. idempotence). For the common single-run case,
/// prefer [runCli].
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

/// Runs the CLI once against an existing [project].
///
/// [args] are CLI flags; the project path is appended automatically, so callers
/// never pass it.
///
/// Verification (`--verify`, on by default in the tool) re-analyzes the whole
/// project with `dart analyze` twice per run. That is orthogonal to what the
/// behavioural suites assert (they pin transformation output and separately
/// check analyze-cleanliness), and doubling the subprocess cost of every run
/// would make the already subprocess-heavy suite far slower. So unless a caller
/// opts in with `--verify`/`--no-verify`, this appends `--no-verify`. The
/// verify feature has its own dedicated suite that opts back in.
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

/// CLI arguments that run **only** [feature], skipping every other pass.
///
/// Produces the transformation's positional name, e.g. `['dot-shorthands']`
/// for `dot_shorthands`. Naming a pass positionally is the CLI's allow-list:
/// only the named pass(es) run.
List<String> onlyFeatureArgs(String feature) => onlyFeaturesArgs({feature});

/// CLI arguments that run **only** the passes named in [features], skipping
/// every other pass.
///
/// The multi-feature generalisation of [onlyFeatureArgs]: each feature's
/// positional transformation name is emitted, e.g.
/// `['dot-shorthands', 'super-parameters']`. Keys are the snake_case
/// fixture-folder names used throughout the harness (see [featureFlags]).
///
/// Use this for cross-feature interaction tests that need a specific subset of
/// passes active at once. Names not present in [featureFlags] are dropped, so a
/// typo silently narrows the selection rather than throwing; callers pass
/// literals drawn from [allFeatures]. An empty [features] selects nothing and so
/// leaves every pass on (the CLI's default), not off.
List<String> onlyFeaturesArgs(Set<String> features) => [
  for (final feature in features) ?featureFlags[feature],
];

/// Creates a throwaway project containing [files] and runs the CLI against it.
///
/// Convenience wrapper over [createProject] + [invokeCli] for the common
/// single-run case. [pubspec] overrides the default pubspec, useful for
/// features (e.g. primary constructors) that require a higher language version.
Future<CliResult> runCli({
  required Map<String, String> files,
  List<String> args = const [],
  String pubspec = defaultPubspec,
}) {
  final project = createProject(files: files, pubspec: pubspec);
  return invokeCli(project, args: args);
}

/// CLI flags that disable a single [feature], leaving all others enabled.
///
/// Two features overlap with sort_members and so disable it too; without that,
/// sort_members would still rewrite the trigger with the target flag off:
///   * `organize_imports`: the analysis server's sortMembers request sorts
///     import directives too, so the two overlap on that operation; and
///   * `sort_constructors_first`: sort_members now also emits constructors
///     first, so it would lift the constructor that the sort_constructors_first
///     trigger relies on staying put.
List<String> withoutFeatureArgs(String feature) => [
  '--no-${featureFlags[feature]}',
  if (feature == 'organize_imports' || feature == 'sort_constructors_first')
    '--no-sort-members',
];

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

  /// Reads back a file by its path relative to the project root.
  ///
  /// Decodes as UTF-8, which drops a leading BOM. Use [readBytes] when a test
  /// needs to see the BOM or the exact line-ending bytes.
  String read(String relativePath) =>
      File(p.join(project.path, relativePath)).readAsStringSync();

  /// Reads back a file's raw bytes, preserving any BOM and the exact line
  /// endings, so byte-level details survive the round trip.
  List<int> readBytes(String relativePath) =>
      File(p.join(project.path, relativePath)).readAsBytesSync();
}
