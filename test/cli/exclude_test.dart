/// Behavioural spec: analysis_options.yaml excludes and --exclude globs
/// prevent matching files from being rewritten.
library;

import 'package:test/test.dart';

import '../support/cli_harness.dart';
import '../support/triggers.dart';

void main() {
  group('file exclusion', () {
    test('analysis_options exclude: pattern skips matching files', () async {
      final result = await runCli(
        files: {
          'lib/widget.dart': dotShorthandsTrigger,
          'test/fixtures/widget.dart': dotShorthandsTrigger,
          'analysis_options.yaml':
              'analyzer:\n  exclude:\n    - test/fixtures/**\n',
        },
        args: onlyFeatureArgs('dot_shorthands'),
      );

      expect(result.exitCode, 0, reason: result.stderr);
      expect(
        result.read('lib/widget.dart'),
        isNot(dotShorthandsTrigger),
        reason: 'lib/widget.dart must be modernized',
      );
      expect(
        result.read('test/fixtures/widget.dart'),
        dotShorthandsTrigger,
        reason: 'excluded file must be left byte-for-byte unchanged',
      );
    });

    test('--exclude glob skips matching files', () async {
      final result = await runCli(
        files: {
          'lib/widget.dart': dotShorthandsTrigger,
          'vendor/widget.dart': dotShorthandsTrigger,
        },
        args: [
          ...onlyFeatureArgs('dot_shorthands'),
          '--exclude',
          'vendor/**',
        ],
      );

      expect(result.exitCode, 0, reason: result.stderr);
      expect(
        result.read('lib/widget.dart'),
        isNot(dotShorthandsTrigger),
        reason: 'lib/widget.dart must be modernized',
      );
      expect(
        result.read('vendor/widget.dart'),
        dotShorthandsTrigger,
        reason: '--exclude glob must prevent the file from being rewritten',
      );
    });

    test('analysis_options and generated-file exclusions compose', () async {
      final result = await runCli(
        files: {
          'lib/widget.dart': dotShorthandsTrigger,
          'lib/widget.g.dart': dotShorthandsTrigger,
          'test/fixtures/widget.dart': dotShorthandsTrigger,
          'analysis_options.yaml':
              'analyzer:\n  exclude:\n    - test/fixtures/**\n',
        },
        args: onlyFeatureArgs('dot_shorthands'),
      );

      expect(result.exitCode, 0, reason: result.stderr);
      expect(
        result.read('lib/widget.dart'),
        isNot(dotShorthandsTrigger),
        reason: 'lib/widget.dart must be modernized',
      );
      expect(
        result.read('lib/widget.g.dart'),
        dotShorthandsTrigger,
        reason: 'generated file must be skipped regardless of analysis_options',
      );
      expect(
        result.read('test/fixtures/widget.dart'),
        dotShorthandsTrigger,
        reason: 'analysis_options-excluded file must be left unchanged',
      );
    });

    test('--exclude and analysis_options excludes compose', () async {
      final result = await runCli(
        files: {
          'lib/widget.dart': dotShorthandsTrigger,
          'test/fixtures/widget.dart': dotShorthandsTrigger,
          'vendor/widget.dart': dotShorthandsTrigger,
          'analysis_options.yaml':
              'analyzer:\n  exclude:\n    - test/fixtures/**\n',
        },
        args: [
          ...onlyFeatureArgs('dot_shorthands'),
          '--exclude',
          'vendor/**',
        ],
      );

      expect(result.exitCode, 0, reason: result.stderr);
      expect(
        result.read('lib/widget.dart'),
        isNot(dotShorthandsTrigger),
        reason: 'lib/widget.dart must be modernized',
      );
      expect(
        result.read('test/fixtures/widget.dart'),
        dotShorthandsTrigger,
        reason: 'analysis_options-excluded file must be unchanged',
      );
      expect(
        result.read('vendor/widget.dart'),
        dotShorthandsTrigger,
        reason: '--exclude file must be unchanged',
      );
    });
  });
}
