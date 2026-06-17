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
/// Assertions are made on **observable behaviour** — the bytes the tool leaves
/// on disk and what it prints — never on private methods. This keeps the test
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
  'switch_expressions',
  'organize_imports',
  'sort_members',
  'fix_all',
];

/// A minimal, dependency-free pubspec that satisfies the tool's validator and
/// lets the analyzer resolve SDK (`dart:`) types without a `pub get`.
const String defaultPubspec = '''
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
  'switch_expressions': 'switch-expressions',
  'organize_imports': 'organize-imports',
  'sort_members': 'sort-members',
  'fix_all': 'fix-all',
};

/// Path to the CLI entry point, relative to [_packageRoot].
const String _binPath = 'bin/dart_modernize.dart';

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
Future<CliResult> invokeCli(
  Directory project, {
  List<String> args = const [],
}) async {
  final result = await Process.run(
    Platform.resolvedExecutable, // the `dart` binary running these tests
    ['run', _binPath, ...args, project.path],
    workingDirectory: _packageRoot,
    stdoutEncoding: systemEncoding,
    stderrEncoding: systemEncoding,
  );

  return CliResult(
    project: project,
    exitCode: result.exitCode,
    stdout: result.stdout as String,
    stderr: result.stderr as String,
  );
}

/// CLI flags that enable **only** [feature], disabling every other pass.
///
/// Produces, e.g. for `dot_shorthands`:
/// `['--no-private-named-parameters', '--no-primary-constructors', ...]`.
List<String> onlyFeatureArgs(String feature) => [
  for (final entry in featureFlags.entries)
    if (entry.key != feature) '--no-${entry.value}',
];

/// Creates a throwaway project containing [files] and runs the CLI against it.
///
/// Convenience wrapper over [createProject] + [invokeCli] for the common
/// single-run case. [pubspec] overrides the default pubspec — useful for
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
List<String> withoutFeatureArgs(String feature) => [
  '--no-${featureFlags[feature]}',
];

/// The outcome of a single CLI invocation against a throwaway project.
final class CliResult {
  /// Root directory of the throwaway project the tool ran against.
  final Directory project;

  /// Process exit code (`0` on success).
  final int exitCode;

  /// Captured standard output.
  final String stdout;

  /// Captured standard error.
  final String stderr;

  CliResult({
    required this.project,
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  /// Whether a file relative to the project root exists.
  bool exists(String relativePath) =>
      File(p.join(project.path, relativePath)).existsSync();

  /// Reads back a file by its path relative to the project root.
  String read(String relativePath) =>
      File(p.join(project.path, relativePath)).readAsStringSync();
}
