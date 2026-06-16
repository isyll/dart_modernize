/// Behavioural spec for `--dry-run` (`-n`): preview only, never write.
library;

import 'package:test/test.dart';

import '../support/cli_harness.dart';
import '../support/triggers.dart';

void main() {
  group('--dry-run', () {
    test('writes nothing to disk', () async {
      final result = await runCli(
        files: {'lib/a.dart': dotShorthandsTrigger},
        args: ['--dry-run', ...onlyFeatureArgs('dot_shorthands')],
      );

      expect(result.exitCode, 0, reason: result.stderr);
      expect(
        result.read('lib/a.dart'),
        dotShorthandsTrigger,
        reason: 'a dry run must leave every source file untouched',
      );
    });

    test('-n is the same as --dry-run and writes nothing', () async {
      final result = await runCli(
        files: {'lib/a.dart': dotShorthandsTrigger},
        args: ['-n', ...onlyFeatureArgs('dot_shorthands')],
      );

      expect(result.exitCode, 0, reason: result.stderr);
      expect(result.read('lib/a.dart'), dotShorthandsTrigger);
    });

    test('emits a unified diff for files that would change', () async {
      final result = await runCli(
        files: {'lib/a.dart': dotShorthandsTrigger},
        args: ['--dry-run', ...onlyFeatureArgs('dot_shorthands')],
      );

      expect(result.exitCode, 0, reason: result.stderr);
      expect(
        result.stdout,
        contains('--- a/'),
        reason: 'dry run should print a unified-diff "---" header',
      );
      expect(
        result.stdout,
        contains('+++ b/'),
        reason: 'dry run should print a unified-diff "+++" header',
      );
    });
  });
}
