/// Regression spec: the finalize `dart format` pass honours the same
/// exclusions as the rest of the pipeline.
///
/// `dart format` does not read `analyzer: exclude:` or the tool's `--exclude`,
/// so a naive `dart format <project>` reformats excluded files. That is exactly
/// how, running the tool on its own repository, golden fixtures under
/// `test/fixtures/**` had blank lines inserted between declarations. The
/// finalize pass must therefore format only the filtered file set.
library;

import 'package:test/test.dart';

import '../support/cli_harness.dart';

void main() {
  group('finalize formatting honours exclusions', () {
    // Valid Dart that `dart format` *would* change: it inserts a blank line
    // between adjacent top-level declarations. If format runs on this file it
    // is no longer byte-identical.
    const unformatted = 'class A {}\nclass B {}\n';

    test('analysis_options-excluded files are not reformatted', () async {
      final result = await runCli(
        files: {
          'lib/app.dart': "final greeting = 'hi';\n",
          'test/fixtures/sample.dart': unformatted,
          'analysis_options.yaml':
              'analyzer:\n  exclude:\n    - test/fixtures/**\n',
        },
      );

      expect(result.exitCode, 0, reason: result.stderr);
      expect(
        result.read('test/fixtures/sample.dart'),
        unformatted,
        reason: 'an excluded file must not be reformatted by dart format',
      );
    });

    test('generated files are not reformatted', () async {
      final result = await runCli(
        files: {
          'lib/app.dart': "final greeting = 'hi';\n",
          'lib/data.g.dart': unformatted,
        },
      );

      expect(result.exitCode, 0, reason: result.stderr);
      expect(
        result.read('lib/data.g.dart'),
        unformatted,
        reason: 'a generated file must not be reformatted by dart format',
      );
    });

    test('--exclude globs are not reformatted', () async {
      final result = await runCli(
        files: {
          'lib/app.dart': "final greeting = 'hi';\n",
          'vendor/sample.dart': unformatted,
        },
        args: const ['--exclude', 'vendor/**'],
      );

      expect(result.exitCode, 0, reason: result.stderr);
      expect(
        result.read('vendor/sample.dart'),
        unformatted,
        reason: 'a --exclude file must not be reformatted by dart format',
      );
    });
  });
}
