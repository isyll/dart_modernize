/// Behavioural spec for the settings that tune a run without switching passes:
/// `options:` (per-pass settings), `line_length:`, `lint_fixes:`, and `format`
/// under `disabled:` in the `dart_modernize:` section, and their CLI
/// counterparts.
library;

import 'package:dart_modernize/dart_modernize.dart';
import 'package:test/test.dart';

import '../support/cli_harness.dart';

CliOptions _parse(
  List<String> args, {
  DartModernizeConfig config = const .empty(),
}) => .fromResults(buildArgParser().parse(args), config: config);

void main() {
  group('defaults', () {
    test('the 0.12 passes are on, unmodifiable-of is off', () {
      final options = _parse([]);
      expect(options.constructorShorthands, isTrue);
      expect(options.emptyBodies, isTrue);
      expect(options.futurePause, isTrue);
      expect(options.wildcardParameters, isTrue);
      expect(options.nullAwareCalls, isTrue);
      expect(options.unmodifiableOf, isFalse);
      expect(_parse(['--unmodifiable-of']).unmodifiableOf, isTrue);
    });

    test('formatting is on, with the project page width', () {
      final options = _parse([]);
      expect(options.format, isTrue);
      expect(options.lineLength, isNull);
      expect(options.dotShorthandConstructors, isTrue);
      expect(options.promoteSuperParameters, isFalse);
      expect(options.lintFixes, isEmpty);
    });
  });

  group('CLI', () {
    test('--no-format turns formatting off', () {
      expect(_parse(['--no-format']).format, isFalse);
    });

    test('--line-length sets the page width', () {
      expect(_parse(['--line-length', '120']).lineLength, 120);
    });

    test('--line-length rejects a non-positive or non-numeric width', () {
      expect(() => _parse(['--line-length', '0']), throwsFormatException);
      expect(() => _parse(['--line-length', 'wide']), throwsFormatException);
    });

    test('--line-length wins over line_length in the config', () {
      final options = _parse([
        '--line-length',
        '100',
      ], config: const .new(lineLength: 120));
      expect(options.lineLength, 100);
    });
  });

  group('config', () {
    test('format under disabled turns formatting off', () {
      final options = _parse([], config: const .new(disabled: {'format'}));
      expect(options.format, isFalse);
      // It is not a pass, so it does not switch any pass off.
      expect(options.dotShorthands, isTrue);
    });

    test('line_length sets the page width', () {
      expect(_parse([], config: const .new(lineLength: 120)).lineLength, 120);
    });

    test('options tune a pass', () {
      final options = _parse(
        [],
        config: const .new(
          passOptions: {
            'dot-shorthands': {'constructors': false},
            'primary-constructors': {'super-parameters': true},
          },
        ),
      );
      expect(options.dotShorthandConstructors, isFalse);
      expect(options.promoteSuperParameters, isTrue);
    });

    test('options for a pass that has none is an error', () {
      expect(
        () => _parse(
          [],
          config: const .new(
            passOptions: {
              'cascades': {'deep': true},
            },
          ),
        ),
        throwsFormatException,
      );
    });

    test('an unknown setting is an error', () {
      expect(
        () => _parse(
          [],
          config: const .new(
            passOptions: {
              'dot-shorthands': {'statics': false},
            },
          ),
        ),
        throwsFormatException,
      );
    });

    test('a setting that is not true or false is an error', () {
      expect(
        () => _parse(
          [],
          config: const .new(
            passOptions: {
              'dot-shorthands': {'constructors': 'no'},
            },
          ),
        ),
        throwsFormatException,
      );
    });

    test('readDartModernizeConfig reads every new key', () {
      final project = createProject(
        files: {
          'analysis_options.yaml': '''
dart_modernize:
  disabled:
    - format
  line_length: 120
  options:
    dot-shorthands:
      constructors: false
  lint_fixes:
    - annotate_overrides
''',
        },
      );
      final config = readDartModernizeConfig(project.path);
      expect(config.disabled, {'format'});
      expect(config.lineLength, 120);
      expect(config.passOptions, {
        'dot-shorthands': {'constructors': false},
      });
      expect(config.lintFixes, ['annotate_overrides']);
    });

    test('a bad line_length exits 64', () async {
      final result = await runCli(
        files: {
          'analysis_options.yaml': 'dart_modernize:\n  line_length: wide\n',
          'lib/a.dart': 'void f() {}\n',
        },
      );
      expect(result.exitCode, 64);
      expect(result.stderr, contains('line_length'));
    });
  });

  test('constructors: false keeps constructor calls written out', () async {
    const source = '''
enum Mode { fast, slow }

class Service {
  const Service();
}

Mode pick() => Mode.fast;

Service make() => const Service();
''';
    final result = await runCli(
      files: {
        'analysis_options.yaml': '''
dart_modernize:
  options:
    dot-shorthands:
      constructors: false
''',
        'lib/a.dart': source,
      },
      args: ['--only', 'dot-shorthands'],
    );
    expect(result.exitCode, 0, reason: result.stderr);
    expect(result.read('lib/a.dart'), contains('Mode pick() => .fast;'));
    expect(
      result.read('lib/a.dart'),
      contains('Service make() => const Service();'),
    );
  });
}
