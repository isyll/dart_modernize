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

    test('files marked with a generated-code header are not fixed', () async {
      // No generated suffix and not named in analysis_options: only the header
      // marks this file generated. `dart fix` cannot see that marker, so this
      // is the case the snapshot-and-restore uniquely protects (the built-in
      // suffixes and analysis_options excludes, `dart fix` would honour itself).
      const generated =
          '// GENERATED CODE - DO NOT MODIFY BY HAND\n\n$fixAllTrigger';
      final result = await runCli(
        files: {
          'lib/app.dart': "final greeting = 'hi';\n",
          'lib/model.dart': generated,
          'analysis_options.yaml': fixAllLints,
        },
        args: onlyFeatureArgs('fix_all'),
      );

      expect(result.exitCode, 0, reason: result.stderr);
      expect(
        result.read('lib/model.dart'),
        generated,
        reason:
            'dart fix cannot see a generated-code header, so the finalize '
            'step must restore a header-marked file byte for byte',
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

    test('one run fixes the included file and spares the excluded one', () async {
      // Both files are fixable in the same invocation: the fix must land on the
      // included file and be rolled back on the excluded one.
      final result = await runCli(
        files: {
          'lib/app.dart': fixAllTrigger,
          'vendor/lib.dart': fixAllTrigger,
          'analysis_options.yaml': fixAllLints,
        },
        args: [...onlyFeatureArgs('fix_all'), '--exclude', 'vendor/**'],
      );

      expect(result.exitCode, 0, reason: result.stderr);
      expect(
        result.read('lib/app.dart'),
        isNot(fixAllTrigger),
        reason: 'the included file must still be fixed',
      );
      expect(
        result.read('vendor/lib.dart'),
        fixAllTrigger,
        reason: 'the excluded file must be left byte for byte identical',
      );
    });
  });
}
