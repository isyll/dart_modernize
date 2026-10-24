/// primary-constructors behaviour that depends on the project around a file:
/// the `super-parameters` setting, and `@immutable` from `package:meta`.
library;

import 'dart:io';

import 'package:test/test.dart';

import '../support/cli_harness.dart';

const _widgets = '''
class Widget {
  const Widget({this.key});

  final Object? key;
}

class Title extends Widget {
  const Title({super.key, required this.text});

  final String text;
}
''';

void main() {
  group('super-parameters setting', () {
    test(
      'is off by default, so a class with super. parameters stays',
      () async {
        final result = await runCli(
          files: {'lib/widgets.dart': _widgets},
          args: ['--only', 'primary-constructors'],
        );
        expect(result.exitCode, 0, reason: result.stderr);
        expect(result.read('lib/widgets.dart'), _widgets);
      },
    );

    test('promotes a class that forwards super. parameters when on', () async {
      final result = await runCli(
        files: {
          'analysis_options.yaml': '''
dart_modernize:
  options:
    primary-constructors:
      super-parameters: true
''',
          'lib/widgets.dart': _widgets,
        },
        args: ['--only', 'primary-constructors'],
      );
      expect(result.exitCode, 0, reason: result.stderr);
      expect(
        result.read('lib/widgets.dart'),
        contains(
          'class const Title({super.key, required final String text}) '
          'extends Widget;',
        ),
      );
    });
  });

  test(
    'leaves a non-const @immutable class that keeps an initialized field',
    () async {
      const source = '''
import 'package:meta/meta.dart';

@immutable
class Base {
  const Base();
}

class Selector extends Base {
  Selector({this.label});

  final String? label;
  final List<int> helper = [];
}

class Plain extends Base {
  Plain({this.label});

  final String? label;
}
''';
      final project = createProject(
        pubspec: '''
name: fixture_project
publish_to: none
environment:
  sdk: ">=3.13.0 <4.0.0"
dependencies:
  meta:
    path: meta
''',
        files: {
          'meta/pubspec.yaml': 'name: meta\nenvironment:\n  sdk: ^3.13.0\n',
          'meta/lib/meta.dart':
              'library meta;\n\n'
              'class Immutable {\n  const Immutable();\n}\n\n'
              'const immutable = Immutable();\n',
          'lib/selector.dart': source,
        },
      );
      final pubGet = await Process.run(Platform.resolvedExecutable, [
        'pub',
        'get',
        '--offline',
      ], workingDirectory: project.path);
      expect(pubGet.exitCode, 0, reason: '${pubGet.stderr}');

      final result = await invokeCli(
        project,
        args: ['--only', 'primary-constructors'],
      );
      expect(result.exitCode, 0, reason: result.stderr);
      final produced = result.read('lib/selector.dart');
      expect(produced, contains('class Selector extends Base {'));
      expect(
        produced,
        contains('class Plain({final String? label}) extends Base;'),
      );
    },
  );
}
