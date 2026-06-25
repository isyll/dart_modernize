/// Behavioural spec for the per-feature `--<flag>` / `--no-<flag>` options.
///
/// For each transformation we assert both directions against a trigger crafted
/// so that *only* that pass would touch it:
///
///   * with only `--<flag>` enabled, the trigger is transformed; and
///   * with `--no-<flag>` (every other pass still enabled), the trigger is left
///     byte-for-byte unchanged.
///
/// Together these prove a flag toggles exactly its own pass, no more, no less.
library;

import 'package:test/test.dart';

import '../support/cli_harness.dart';
import '../support/triggers.dart';

void main() {
  for (final feature in allFeatures) {
    final flag = featureFlags[feature]!;

    group('--$flag', () {
      test('enabling it applies the $feature pass', () async {
        final result = await runCli(
          files: triggerFiles(feature),
          args: onlyFeatureArgs(feature),
          pubspec: triggerPubspec(feature),
        );

        expect(result.exitCode, 0, reason: result.stderr);
        expect(
          result.read('lib/trigger.dart'),
          isNot(triggers[feature]),
          reason:
              'with only --$flag enabled, the $feature pass must transform '
              'its trigger file',
        );
      });

      test('--no-$flag skips the $feature pass', () async {
        final result = await runCli(
          files: triggerFiles(feature),
          args: withoutFeatureArgs(feature),
          pubspec: defaultPubspec,
        );

        expect(result.exitCode, 0, reason: result.stderr);
        expect(
          result.read('lib/trigger.dart'),
          triggers[feature],
          reason:
              'with --no-$flag, no other (still-enabled) pass may modify the '
              '$feature trigger',
        );
      });
    });
  }
}
