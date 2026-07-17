/// Behavioural spec for `--check`: write nothing and exit non-zero when any
/// file would change, so the tool can gate CI (issue #13).
library;

import 'package:test/test.dart';

import '../support/cli_harness.dart';
import '../support/triggers.dart';

/// A file `expression-bodies` collapses to `int square(int x) => x * x;`.
const _needsChange = expressionBodiesTrigger;

/// The same file already in its modern form; no pass touches it.
const _alreadyModern = 'int square(int x) => x * x;\n';

void main() {
  group('--check', () {
    test(
      'exits non-zero and writes nothing when a file would change',
      () async {
        final result = await runCli(
          files: {'lib/a.dart': _needsChange},
          args: ['--check', ...onlyFeatureArgs('expression_bodies')],
        );

        expect(
          result.exitCode,
          isNonZero,
          reason: 'must fail when work remains',
        );
        expect(
          result.read('lib/a.dart'),
          _needsChange,
          reason: '--check must not write any file',
        );
        expect(result.stdout, contains('would change'));
      },
    );

    test('exits zero when nothing would change', () async {
      final result = await runCli(
        files: {'lib/a.dart': _alreadyModern},
        args: ['--check', ...onlyFeatureArgs('expression_bodies')],
      );

      expect(result.exitCode, 0, reason: result.stderr);
      expect(result.read('lib/a.dart'), _alreadyModern);
      expect(result.stdout, contains('Already modern'));
    });

    test('on its own prints a summary but no diff', () async {
      final result = await runCli(
        files: {'lib/a.dart': _needsChange},
        args: ['--check', ...onlyFeatureArgs('expression_bodies')],
      );

      expect(result.exitCode, isNonZero);
      expect(
        result.stdout,
        isNot(contains('--- a/')),
        reason: '--check alone must stay quiet apart from the summary line',
      );
    });

    test(
      'composes with --dry-run: prints the diff and sets the exit code',
      () async {
        final result = await runCli(
          files: {'lib/a.dart': _needsChange},
          args: [
            '--check',
            '--dry-run',
            ...onlyFeatureArgs('expression_bodies'),
          ],
        );

        expect(
          result.exitCode,
          isNonZero,
          reason: '--check still gates the exit',
        );
        expect(
          result.read('lib/a.dart'),
          _needsChange,
          reason: 'still a preview: nothing is written',
        );
        expect(
          result.stdout,
          contains('--- a/'),
          reason: 'dry-run prints a diff',
        );
        expect(result.stdout, contains('+++ b/'));
      },
    );

    test('with --dry-run on an already-modern file exits zero', () async {
      final result = await runCli(
        files: {'lib/a.dart': _alreadyModern},
        args: ['--check', '--dry-run', ...onlyFeatureArgs('expression_bodies')],
      );

      expect(result.exitCode, 0, reason: result.stderr);
      expect(result.read('lib/a.dart'), _alreadyModern);
    });
  });
}
