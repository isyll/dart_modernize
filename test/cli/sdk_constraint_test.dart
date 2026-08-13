/// Behavioural spec: the tool emits 3.13+ idioms, so it refuses to touch a
/// project whose SDK constraint admits an older Dart version, and rejects a
/// constraint it cannot parse. In every rejection the source is left untouched.
library;

import 'package:test/test.dart';

import '../support/cli_harness.dart';

void main() {
  group('SDK constraint validation', () {
    const source = 'void f() {}\n';

    test('a constraint allowing an older SDK is rejected and nothing is '
        'written', () async {
      final result = await runCli(
        files: {'lib/a.dart': source},
        pubspec: '''
name: fixture_project
environment:
  sdk: ">=3.0.0 <4.0.0"
''',
      );

      expect(result.exitCode, 1);
      expect(result.stderr, contains('Error:'));
      expect(result.stderr, contains('3.13.0'));
      expect(result.read('lib/a.dart'), source);
    });

    test(
      'an unparseable constraint is rejected and nothing is written',
      () async {
        final result = await runCli(
          files: {'lib/a.dart': source},
          pubspec: '''
name: fixture_project
environment:
  sdk: "not a version"
''',
        );

        expect(result.exitCode, 1);
        expect(result.stderr, contains('Error:'));
        expect(result.read('lib/a.dart'), source);
      },
    );

    test('a constraint pinned to exactly 3.13.0 is accepted', () async {
      final result = await runCli(
        files: {'lib/a.dart': source},
        pubspec: '''
name: fixture_project
environment:
  sdk: ">=3.13.0 <4.0.0"
''',
      );

      expect(result.exitCode, 0);
    });

    test('3.12.0 is now below the floor and is rejected', () async {
      // 3.12 was the floor until primary constructors went stable in 3.13 and
      // the promotion pass started emitting that syntax.
      final result = await runCli(
        files: {'lib/a.dart': source},
        pubspec: '''
name: fixture_project
environment:
  sdk: ">=3.12.0 <4.0.0"
''',
      );

      expect(result.exitCode, 1);
      expect(result.stderr, contains('3.13.0'));
      expect(result.read('lib/a.dart'), source);
    });
  });
}
