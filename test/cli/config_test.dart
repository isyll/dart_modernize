/// Behavioural spec for the `dart_modernize:` section of `analysis_options.yaml`.
///
/// The section records, per project, which passes to switch on or off and which
/// extra paths to skip. Three layers are covered:
///   * reading: `readDartModernizeConfig` pulls `enabled` / `disabled` /
///     `exclude` out of the file, and returns empty when the file or section is
///     absent;
///   * layering: `CliOptions.fromResults` applies the config under the CLI, so a
///     flag always wins, and rejects unknown or contradictory names; and
///   * end-to-end: the real binary honors the file, and a CLI flag overrides it.
library;

import 'package:dart_modernize/dart_modernize.dart';
import 'package:test/test.dart';

import '../support/cli_harness.dart';
import '../support/triggers.dart';

void main() {
  group('readDartModernizeConfig', () {
    test('reads enabled, disabled, and exclude lists', () {
      final project = createProject(
        files: {
          'analysis_options.yaml': '''
dart_modernize:
  enabled:
    - sort-members
  disabled:
    - organize-imports
  exclude:
    - lib/generated/**
    - lib/vendor/**
''',
        },
      );

      final config = readDartModernizeConfig(project.path);
      expect(config.enabled, {'sort-members'});
      expect(config.disabled, {'organize-imports'});
      expect(config.excludes, ['lib/generated/**', 'lib/vendor/**']);
    });

    test('is empty when there is no analysis_options.yaml', () {
      final project = createProject(files: {'lib/a.dart': 'void f() {}\n'});
      expect(readDartModernizeConfig(project.path).isEmpty, isTrue);
    });

    test('is empty when the file has no dart_modernize section', () {
      final project = createProject(
        files: {
          'analysis_options.yaml': 'analyzer:\n  exclude:\n    - build/**\n',
        },
      );
      expect(readDartModernizeConfig(project.path).isEmpty, isTrue);
    });
  });

  group('config layering in CliOptions', () {
    test('config disabled turns an on-by-default pass off', () {
      final options = _parse(
        [],
        config: const DartModernizeConfig(disabled: {'cascades'}),
      );
      expect(options.cascades, isFalse);
      // Other passes stay at their default.
      expect(options.dotShorthands, isTrue);
    });

    test('config enabled turns an off-by-default pass on', () {
      final options = _parse(
        [],
        config: const DartModernizeConfig(enabled: {'sort-members'}),
      );
      expect(options.sortMembers, isTrue);
    });

    test('a CLI --only set overrides the config', () {
      // Config disables dot-shorthands, but naming it with --only runs it: the
      // CLI wins, and --only is the absolute base so the config no longer
      // contributes.
      final options = _parse([
        '--only',
        'dot-shorthands',
      ], config: const DartModernizeConfig(disabled: {'dot-shorthands'}));
      expect(options.dotShorthands, isTrue);
      expect(options.cascades, isFalse);
    });

    test('a CLI switch overrides the config in its direction', () {
      // Config enables sort-members; --only nothing, so config sets the base on,
      // but there is no --no-sort-members to force it off (that needs --only).
      // The reverse works: config need not enable a pass for --sort-members to.
      final off = _parse([
        '--no-organize-imports',
      ], config: const DartModernizeConfig(enabled: {'organize-imports'}));
      expect(off.organizeImports, isFalse, reason: 'CLI --no- beats config');
    });

    test('config excludes are merged ahead of the CLI excludes', () {
      final options = _parse([
        '--exclude',
        'lib/cli/**',
      ], config: const DartModernizeConfig(excludes: ['lib/config/**']));
      expect(options.excludes, ['lib/config/**', 'lib/cli/**']);
    });

    test('an unknown config name throws a FormatException', () {
      expect(
        () => _parse(
          [],
          config: const DartModernizeConfig(disabled: {'not-a-pass'}),
        ),
        throwsFormatException,
      );
    });

    test('a name in both enabled and disabled throws a FormatException', () {
      expect(
        () => _parse(
          [],
          config: const DartModernizeConfig(
            enabled: {'cascades'},
            disabled: {'cascades'},
          ),
        ),
        throwsFormatException,
      );
    });
  });

  group('config end-to-end', () {
    test('disabled in the file skips that pass, others still run', () async {
      final result = await runCli(
        files: {
          'analysis_options.yaml':
              'dart_modernize:\n  disabled:\n    - string-interpolation\n',
          'lib/interp.dart': stringInterpolationTrigger,
          'lib/dot.dart': dotShorthandsTrigger,
        },
      );

      expect(result.exitCode, 0, reason: result.stderr);
      // The disabled pass left its trigger byte-for-byte intact.
      expect(result.read('lib/interp.dart'), stringInterpolationTrigger);
      // A pass not disabled still fired.
      expect(result.read('lib/dot.dart'), isNot(dotShorthandsTrigger));
    });

    test('enabled in the file switches on an off-by-default pass', () async {
      final result = await runCli(
        files: {
          'analysis_options.yaml':
              'dart_modernize:\n  enabled:\n    - sort-members\n',
          'lib/s.dart': sortMembersTrigger,
        },
      );

      expect(result.exitCode, 0, reason: result.stderr);
      // sort-members ran purely from the config: alpha now precedes beta.
      expect(
        result.read('lib/s.dart'),
        stringContainsInOrder(['void alpha', 'void beta']),
      );
    });

    test('exclude in the file skips matching files', () async {
      final result = await runCli(
        files: {
          'analysis_options.yaml':
              'dart_modernize:\n  exclude:\n    - lib/vendor/**\n',
          'lib/vendor/gen.dart': dotShorthandsTrigger,
          'lib/main.dart': dotShorthandsTrigger,
        },
      );

      expect(result.exitCode, 0, reason: result.stderr);
      // Excluded file untouched; the other one modernized.
      expect(result.read('lib/vendor/gen.dart'), dotShorthandsTrigger);
      expect(result.read('lib/main.dart'), isNot(dotShorthandsTrigger));
    });

    test('a CLI flag overrides the config file', () async {
      final result = await runCli(
        files: {
          'analysis_options.yaml':
              'dart_modernize:\n  disabled:\n    - dot-shorthands\n',
          'lib/dot.dart': dotShorthandsTrigger,
        },
        // --only names the pass the file disabled: the CLI wins.
        args: ['--only', 'dot-shorthands'],
      );

      expect(result.exitCode, 0, reason: result.stderr);
      expect(result.read('lib/dot.dart'), isNot(dotShorthandsTrigger));
    });

    test(
      'an unknown pass name in the file exits 64 with a help hint',
      () async {
        final result = await runCli(
          files: {
            'analysis_options.yaml':
                'dart_modernize:\n  disabled:\n    - not-a-pass\n',
            'lib/a.dart': 'void f() {}\n',
          },
        );

        expect(result.exitCode, 64);
        expect(result.stderr, contains('Error:'));
        expect(result.stderr, contains('dart_modernize --help'));
        expect(result.read('lib/a.dart'), 'void f() {}\n');
      },
    );
  });
}

CliOptions _parse(
  List<String> args, {
  DartModernizeConfig config = const DartModernizeConfig.empty(),
}) => .fromResults(buildArgParser().parse(args), config: config);
