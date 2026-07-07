/// Behavioural spec: an unsupported flag or a malformed invocation is
/// rejected with a formatted error and a hint to run `--help`, never a
/// stack trace.
library;

import 'package:test/test.dart';

import '../support/cli_harness.dart';

void main() {
  group('invalid arguments', () {
    test('unknown long flag exits 64 with an error and a help hint', () async {
      final result = await runCli(
        files: {'lib/a.dart': 'void f() {}\n'},
        args: ['--not-a-flag'],
      );

      expect(result.exitCode, 64);
      expect(result.stdout, isEmpty);
      expect(result.stderr, contains('Error:'));
      expect(result.stderr, contains('dart_modernize --help'));
    });

    test('unknown short flag exits 64 with an error and a help hint', () async {
      final result = await runCli(
        files: {'lib/a.dart': 'void f() {}\n'},
        args: ['-x'],
      );

      expect(result.exitCode, 64);
      expect(result.stdout, isEmpty);
      expect(result.stderr, contains('Error:'));
      expect(result.stderr, contains('dart_modernize --help'));
    });

    test('a value given to a flag that takes none exits 64 with an error and '
        'a help hint', () async {
      final result = await runCli(
        files: {'lib/a.dart': 'void f() {}\n'},
        args: ['--dry-run=true'],
      );

      expect(result.exitCode, 64);
      expect(result.stdout, isEmpty);
      expect(result.stderr, contains('Error:'));
      expect(result.stderr, contains('dart_modernize --help'));
    });

    test('no file is written when argument parsing fails', () async {
      final result = await runCli(
        files: {'lib/a.dart': 'void f() {}\n'},
        args: ['--not-a-flag'],
      );

      expect(result.exitCode, 64);
      expect(result.read('lib/a.dart'), 'void f() {}\n');
    });
  });
}
