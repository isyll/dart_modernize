/// Passes that read the project around a file, not just the file: whether it
/// is a published package, and which lints it enables.
library;

import 'package:test/test.dart';

import '../support/cli_harness.dart';

const _staticHolder = '''
class Constants {
  const Constants._();

  static const maxRetries = 3;
}
''';

void main() {
  group('abstract-final-classes', () {
    test('leaves the public API of a published package alone', () async {
      final result = await runCli(
        pubspec: '''
name: shared_kit
environment:
  sdk: ">=3.13.0 <4.0.0"
''',
        files: {
          'lib/shared_kit.dart': "export 'src/public.dart';\n",
          'lib/src/public.dart': _staticHolder,
          'lib/src/internal.dart': _staticHolder.replaceAll(
            'Constants',
            'Internal',
          ),
        },
        args: ['--only', 'abstract-final-classes'],
      );

      expect(result.exitCode, 0, reason: result.stderr);
      expect(result.read('lib/src/public.dart'), _staticHolder);
      expect(
        result.read('lib/src/internal.dart'),
        contains('abstract final class Internal'),
      );
    });

    test('keeps the private constructor when the project enables '
        'avoid_classes_with_only_static_members', () async {
      final result = await runCli(
        files: {
          'analysis_options.yaml': '''
linter:
  rules:
    - avoid_classes_with_only_static_members
''',
          'lib/constants.dart': _staticHolder,
        },
        args: ['--only', 'abstract-final-classes'],
      );

      expect(result.exitCode, 0, reason: result.stderr);
      expect(result.read('lib/constants.dart'), '''
abstract final class Constants {
  const Constants._();

  static const maxRetries = 3;
}
''');
    });
  });
}
