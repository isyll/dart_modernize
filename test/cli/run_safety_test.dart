/// Behavioural spec for what protects a project around a run: the backup and
/// `--restore`, formatting only what changed, a library pinned to an old
/// language version, `--upgrade-sdk`, `lint_fixes`, and the report of new
/// infos.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/cli_harness.dart';
import '../support/triggers.dart';

/// Unformatted on purpose, and untouched by every pass.
const _unformatted = 'int   add(int a,int b)=>a+b;\n';

void main() {
  group('backup', () {
    test('--restore with nothing saved says so', () async {
      final result = await runCli(
        files: {'lib/a.dart': expressionBodiesTrigger},
        args: ['--restore'],
      );
      expect(result.exitCode, 0, reason: result.stderr);
      expect(result.stdout, contains('Nothing to restore.'));
      expect(result.read('lib/a.dart'), expressionBodiesTrigger);
    });

    test('an interrupted run blocks the next one until --restore', () async {
      final project = createProject(
        files: {
          'lib/a.dart': 'int square(int x) => x * x;\n',
          '.dart_tool/dart_modernize/backup/files/lib/a.dart.bak':
              expressionBodiesTrigger,
          '.dart_tool/dart_modernize/backup/manifest.json': jsonManifest([
            'lib/a.dart',
          ]),
        },
      );

      final blocked = await invokeCli(project);
      expect(blocked.exitCode, 1);
      expect(blocked.stderr, contains('--restore'));

      final restored = await invokeCli(project, args: ['--restore']);
      expect(restored.exitCode, 0, reason: restored.stderr);
      expect(restored.stdout, contains('Restored 1 file.'));
      expect(restored.read('lib/a.dart'), expressionBodiesTrigger);
      expect(
        Directory(
          p.join(project.path, '.dart_tool', 'dart_modernize', 'backup'),
        ).existsSync(),
        isFalse,
      );
    });

    test('a failure after the files were written puts them back', () async {
      final result = await runCli(
        files: {
          'analysis_options.yaml':
              'dart_modernize:\n'
              '  lint_fixes:\n'
              '    - no_such_lint\n',
          'lib/a.dart': expressionBodiesTrigger,
        },
        args: ['--only', 'expression-bodies,fix-all'],
      );
      expect(result.exitCode, 1);
      expect(result.read('lib/a.dart'), expressionBodiesTrigger);
      expect(
        result.exists('.dart_tool/dart_modernize/backup/manifest.json'),
        isFalse,
      );
    });
  });

  group('format', () {
    test('formats only the files the run changed', () async {
      final result = await runCli(
        files: {
          'lib/changed.dart': 'int   square(int x) {\n  return x * x;\n}\n',
          'lib/untouched.dart': _unformatted,
        },
        args: ['--only', 'expression-bodies'],
      );
      expect(result.exitCode, 0, reason: result.stderr);
      expect(result.read('lib/changed.dart'), 'int square(int x) => x * x;\n');
      expect(result.read('lib/untouched.dart'), _unformatted);
    });

    test('--no-format leaves the layout to the project', () async {
      final result = await runCli(
        files: {
          'lib/changed.dart': 'int   square(int x) {\n  return x * x;\n}\n',
        },
        args: ['--only', 'expression-bodies', '--no-format'],
      );
      expect(result.exitCode, 0, reason: result.stderr);
      expect(
        result.read('lib/changed.dart'),
        'int   square(int x) => x * x;\n',
      );
    });

    test('--line-length sets the page width', () async {
      const long =
          'String describe(String first, String second) {\n'
          "  return first + ' and ' + second + ' and more words here';\n"
          '}\n';
      final result = await runCli(
        files: {'lib/long.dart': long},
        args: ['--only', 'expression-bodies', '--line-length', '120'],
      );
      expect(result.exitCode, 0, reason: result.stderr);
      expect(
        result.read('lib/long.dart'),
        "String describe(String first, String second) => first + ' and ' + "
        "second + ' and more words here';\n",
      );
    });
  });

  test('leaves a library pinned to an older language version alone', () async {
    const legacy = '''
// @dart = 2.12
class Base {
  final int x;
  Base(this.x);
}

class Derived extends Base {
  Derived(int x) : super(x);
}

int square(int x) {
  return x * x;
}
''';
    final result = await runCli(files: {'lib/legacy.dart': legacy});
    expect(result.exitCode, 0, reason: result.stderr);
    expect(result.read('lib/legacy.dart'), legacy);
  });

  test(
    '--upgrade-sdk raises the constraint and drops illegal modifiers',
    () async {
      final project = createProject(
        pubspec:
            'name: fixture_project\npublish_to: none\n'
            'environment:\n  sdk: ">=3.7.0 <4.0.0"\n',
        files: {'lib/a.dart': 'int twice(final int x) => x * 2;\n'},
      );
      final result = await invokeCli(
        project,
        args: ['--upgrade-sdk', '--only', 'expression-bodies'],
      );
      expect(result.exitCode, 0, reason: result.stderr);
      expect(result.stdout, contains('Raised the SDK constraint'));
      expect(result.read('pubspec.yaml'), contains('sdk: ^3.13.0'));
      expect(result.read('lib/a.dart'), 'int twice(int x) => x * 2;\n');
    },
  );

  test('lint_fixes applies a lint the project does not enable', () async {
    const options =
        'dart_modernize:\n  lint_fixes:\n    - annotate_overrides\n';
    final result = await runCli(
      files: {'analysis_options.yaml': options, 'lib/a.dart': fixAllTrigger},
      args: ['--only', 'fix-all'],
    );
    expect(result.exitCode, 0, reason: result.stderr);
    expect(result.read('lib/a.dart'), contains('@override'));
    expect(result.read('analysis_options.yaml'), options);
  });

  test('reports a new info it caused, and keeps the change', () async {
    final result = await runCli(
      files: {
        'analysis_options.yaml':
            'linter:\n  rules:\n    - always_specify_types\n',
        'lib/a.dart': "void f() {\n  final String s = 'a';\n  print(s);\n}\n",
      },
      args: ['--only', 'prefer-inferred-types', '--verify'],
    );
    expect(result.exitCode, 0, reason: result.stderr);
    expect(result.read('lib/a.dart'), contains("final s = 'a';"));
    expect(result.stdout, contains('new warning or info'));
    expect(result.stdout.toLowerCase(), contains('always_specify_types'));
  });
}

/// The manifest a backup writes, listing project-relative paths.
String jsonManifest(List<String> paths) =>
    '[${paths.map((path) => '"$path"').join(',')}]';
