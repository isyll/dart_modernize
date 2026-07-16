/// Regression spec: the finalize `dart fix --apply` pass honours the same
/// exclusions as the rest of the pipeline.
///
/// `dart fix --apply` is given the project root, not a file list, so a naive
/// invocation fixes excluded files too. That is exactly how, running with
/// `--exclude "lib/legacy/**"`, a file the rest of the pipeline skips still
/// got `@override` added by `dart fix`. The finalize pass must therefore
/// snapshot and restore anything `dart fix` would otherwise reach outside the
/// filtered file set.
library;

import 'package:test/test.dart';

import '../support/cli_harness.dart';
import '../support/triggers.dart';

void main() {
  group('finalize dart fix --apply honours exclusions', () {
    test('analysis_options-excluded files are not fixed', () async {
      final result = await runCli(
        files: {
          'lib/app.dart': "final greeting = 'hi';\n",
          'test/fixtures/trigger.dart': fixAllTrigger,
          'analysis_options.yaml':
              '${fixAllLints}analyzer:\n  exclude:\n    - test/fixtures/**\n',
        },
        args: onlyFeatureArgs('fix_all'),
      );

      expect(result.exitCode, 0, reason: result.stderr);
      expect(
        result.read('test/fixtures/trigger.dart'),
        fixAllTrigger,
        reason: 'an excluded file must not be fixed by dart fix --apply',
      );
    });

    test('generated files are not fixed', () async {
      final result = await runCli(
        files: {
          'lib/app.dart': "final greeting = 'hi';\n",
          'lib/trigger.g.dart': fixAllTrigger,
          'analysis_options.yaml': fixAllLints,
        },
        args: onlyFeatureArgs('fix_all'),
      );

      expect(result.exitCode, 0, reason: result.stderr);
      expect(
        result.read('lib/trigger.g.dart'),
        fixAllTrigger,
        reason: 'a generated file must not be fixed by dart fix --apply',
      );
    });

    test('--exclude globs are not fixed', () async {
      final result = await runCli(
        files: {
          'lib/app.dart': "final greeting = 'hi';\n",
          'vendor/trigger.dart': fixAllTrigger,
          'analysis_options.yaml': fixAllLints,
        },
        args: [...onlyFeatureArgs('fix_all'), '--exclude', 'vendor/**'],
      );

      expect(result.exitCode, 0, reason: result.stderr);
      expect(
        result.read('vendor/trigger.dart'),
        fixAllTrigger,
        reason: 'a --exclude file must not be fixed by dart fix --apply',
      );
    });

    test('non-excluded files are still fixed', () async {
      final result = await runCli(
        files: {
          'lib/trigger.dart': fixAllTrigger,
          'analysis_options.yaml': fixAllLints,
        },
        args: onlyFeatureArgs('fix_all'),
      );

      expect(result.exitCode, 0, reason: result.stderr);
      expect(
        result.read('lib/trigger.dart'),
        isNot(fixAllTrigger),
        reason: 'a non-excluded file must still be fixed by dart fix --apply',
      );
    });
  });
}
