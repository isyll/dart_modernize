/// Behavioural spec for the verify step (`--verify`, on by default).
///
/// After editing, the tool re-analyzes with `dart analyze` and reverts any
/// changed file that gained an error, so a run can never leave a file on disk
/// that no longer compiles. The trigger here is primary-constructors: on a
/// default-SDK project its output uses experiment-gated syntax that does not
/// compile, which is exactly the "a pass produced code that no longer analyzes"
/// case verify must catch.
///
/// These tests opt into verification explicitly (with `--verify`), because the
/// shared harness appends `--no-verify` by default to keep the rest of the
/// suite fast (see [invokeCli]).
library;

import 'package:test/test.dart';

import '../support/analysis_helper.dart';
import '../support/cli_harness.dart';

void main() {
  // A class primary-constructors promotes to `class Point(final int x, ...)`.
  // Under the default SDK that syntax needs an experiment, so the rewritten
  // file no longer compiles.
  const eligible = '''
class Point {
  final int x;
  final int y;

  Point(this.x, this.y);
}
''';

  test(
    'reverts a file that would no longer compile and exits non-zero',
    () async {
      final result = await runCli(
        files: {'lib/point.dart': eligible},
        args: ['--only', 'primary-constructors', '--verify'],
      );

      expect(result.exitCode, isNonZero);
      expect(
        result.read('lib/point.dart'),
        eligible,
        reason:
            'a file that stopped compiling must be restored to its original',
      );
      expect(result.stderr, contains('point.dart'));
      expect(result.stderr, contains('Reverted'));
    },
  );

  test('--no-verify keeps the change and exits zero', () async {
    final result = await runCli(
      files: {'lib/point.dart': eligible},
      args: ['--only', 'primary-constructors', '--no-verify'],
    );

    expect(result.exitCode, 0, reason: result.stderr);
    expect(
      result.read('lib/point.dart'),
      isNot(eligible),
      reason:
          'with --no-verify the rewrite is kept even though it will not '
          'analyze clean',
    );
    expect(result.read('lib/point.dart'), contains('class Point('));
  });

  test('a valid modernization passes verification and is kept', () async {
    // No primary-constructor-eligible class here, so every pass produces code
    // that still compiles; verification must keep all of it.
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
