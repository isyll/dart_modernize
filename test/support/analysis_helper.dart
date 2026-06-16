/// Helper for the semantic-safety test: confirm a project analyzes cleanly.
///
/// Modernization must be a *syntactic* change only — it may never introduce a
/// new analyzer error. [analyzeProject] runs the real `dart analyze` over a
/// project and reports the outcome so a test can assert the transformed code is
/// still well-typed and valid.
library;

import 'dart:io';

/// The result of running `dart analyze` over a project.
typedef AnalysisOutcome = ({int exitCode, String output});

/// Runs `dart analyze` on [project] and returns its exit code and combined
/// output.
///
/// A best-effort `dart pub get` runs first so package resolution exists; it is
/// offline and instant for the dependency-free fixture projects used here, and
/// its failure (e.g. no network) is ignored — `dart analyze` still resolves SDK
/// (`dart:`) libraries on its own.
///
/// `dart analyze` exits non-zero on any error or warning, so an exit code of `0`
/// means the project is clean.
Future<AnalysisOutcome> analyzeProject(Directory project) async {
  await Process.run(Platform.resolvedExecutable, [
    'pub',
    'get',
  ], workingDirectory: project.path);

  final result = await Process.run(
    Platform.resolvedExecutable,
    ['analyze', project.path],
    stdoutEncoding: systemEncoding,
    stderrEncoding: systemEncoding,
  );

  return (
    exitCode: result.exitCode,
    output: '${result.stdout}${result.stderr}',
  );
}
