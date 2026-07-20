/// Behavioural spec for selecting or disabling a single pass.
///
/// For each transformation we assert both directions against a trigger crafted
/// so that *only* that pass would touch it:
///
///   * with `--only <name>` (just that pass selected), the trigger is
///     transformed; and
///   * with that pass off (its `--no-<name>` switch, or simply a default run
///     for an off-by-default pass), every other pass still runs and the trigger
///     is left byte-for-byte unchanged.
///
/// Together these prove selecting or leaving out a pass affects exactly that
/// pass, no more, no less.
library;

import 'package:test/test.dart';

import '../support/cli_harness.dart';
import '../support/triggers.dart';

void main() {
  for (final feature in allFeatures) {
    final flag = featureFlags[feature]!;

    group(flag, () {
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
              'with only the $feature pass selected, it must transform its '
              'trigger file',
        );
      });

      final off = defaultOffFeatures.contains(feature);
      test(
        off
            ? 'it stays off in a default run'
            : '--no-$flag skips the $feature pass',
        () async {
          final result = await runCli(
            files: triggerFiles(feature),
            args: withoutFeatureArgs(feature),
            pubspec: defaultPubspec,
          );

          expect(result.exitCode, 0, reason: result.stderr);
          expect(
            result.read('lib/trigger.dart'),
            triggers[feature],
            reason: off
                ? '$feature is off by default, so a default run must not touch '
                      'its trigger'
                : 'with --no-$flag, no other (still-enabled) pass may modify the '
                      '$feature trigger',
          );
        },
      );
    });
  }
}
