/// Behavioural spec for the verify step (`--verify`, on by default).
///
/// After editing, the tool re-analyzes with `dart analyze` and reverts any
/// changed file that gained an error, so a run can never leave a file on disk
/// that no longer compiles.
///
/// The trigger is a library pinned to an older language version with a
/// `// @dart=` comment. Dot shorthands arrived in 3.10, and that pass does not
/// check the language version, so on a 3.9 library it writes `.fast`, which
/// cannot compile there. That is exactly the case verify has to catch.
///
/// These tests opt into verification explicitly (with `--verify`), because the
/// shared harness appends `--no-verify` by default to keep the rest of the
/// suite fast (see [invokeCli]).
library;

import 'package:test/test.dart';

import '../support/analysis_helper.dart';
import '../support/cli_harness.dart';

void main() {
  // Pinned to 3.9, where dot shorthands do not exist yet. dot-shorthands still
  // rewrites `Mode.fast` to `.fast`, and the result does not compile.
  const eligible = '''
// @dart=3.9
enum Mode { fast, slow }

Mode pick() {
  Mode m = Mode.fast;
  return m;
}
''';

  test(
    'reverts a file that would no longer compile and exits non-zero',
    () async {
      final result = await runCli(
        files: {'lib/legacy.dart': eligible},
        args: ['--only', 'dot-shorthands', '--verify'],
      );

      expect(result.exitCode, isNonZero);
      expect(
        result.read('lib/legacy.dart'),
        eligible,
        reason:
            'a file that stopped compiling must be restored to its original',
      );
      expect(result.stderr, contains('legacy.dart'));
      expect(result.stderr, contains('Reverted'));
    },
  );

  test('--no-verify keeps the change and exits zero', () async {
    final result = await runCli(
      files: {'lib/legacy.dart': eligible},
      args: ['--only', 'dot-shorthands', '--no-verify'],
    );

    expect(result.exitCode, 0, reason: result.stderr);
    expect(
      result.read('lib/legacy.dart'),
      isNot(eligible),
      reason:
          'with --no-verify the rewrite is kept even though it will not '
          'analyze clean',
    );
    expect(result.read('lib/legacy.dart'), contains('= .fast;'));
  });

  test('a valid modernization passes verification and is kept', () async {
    // Nothing pinned to an old language version here, so every pass produces
    // code that still compiles and verification keeps all of it.
    const clean = '''
enum Mode { fast, slow }

Mode pick() => Mode.fast;

String greet(String name) => 'Hello, ' + name + '!';
''';

    final project = createProject(files: {'lib/app.dart': clean});
    final run = await invokeCli(project, args: const ['--verify']);

    expect(run.exitCode, 0, reason: run.stderr);
    expect(
      run.read('lib/app.dart'),
      isNot(clean),
      reason: 'the valid passes must still apply under verification',
    );
    // dot-shorthands and string-interpolation both fired and were kept.
    expect(run.read('lib/app.dart'), contains('=> .fast;'));
    expect(run.read('lib/app.dart'), contains(r"'Hello, $name!'"));

    final after = await analyzeProject(project);
    expect(
      after.exitCode,
      0,
      reason: 'kept output must analyze clean:\n${after.output}',
    );
  });
}
