import 'package:dart_modernize/dart_modernize.dart';
import 'package:test/test.dart';

void main() {
  group('buildArgParser / CliOptions', () {
    test('all transformations are enabled by default', () {
      final options = CliOptions.fromResults(buildArgParser().parse([]));

      expect(options.dryRun, isFalse);
      expect(options.dotShorthands, isTrue);
      expect(options.privateNamedParameters, isTrue);
      expect(options.primaryConstructors, isTrue);
      expect(options.organizeImports, isTrue);
      expect(options.sortMembers, isTrue);
      expect(options.fixAll, isTrue);
    });

    test('--dry-run enables dry-run mode', () {
      final options = CliOptions.fromResults(
        buildArgParser().parse(['--dry-run']),
      );
      expect(options.dryRun, isTrue);
    });

    test('-n is an alias for --dry-run', () {
      final options = CliOptions.fromResults(buildArgParser().parse(['-n']));
      expect(options.dryRun, isTrue);
    });

    test('--no-primary-constructors disables only that transformation', () {
      final options = CliOptions.fromResults(
        buildArgParser().parse(['--no-primary-constructors']),
      );
      expect(options.primaryConstructors, isFalse);
      // others unaffected
      expect(options.dotShorthands, isTrue);
      expect(options.fixAll, isTrue);
    });

    test('multiple --no-* flags disable independent transformations', () {
      final options = CliOptions.fromResults(
        buildArgParser().parse([
          '--no-dot-shorthands',
          '--no-organize-imports',
          '--no-fix-all',
        ]),
      );
      expect(options.dotShorthands, isFalse);
      expect(options.organizeImports, isFalse);
      expect(options.fixAll, isFalse);
      // others still on
      expect(options.primaryConstructors, isTrue);
      expect(options.sortMembers, isTrue);
    });

    test('positional path argument is captured', () {
      final options = CliOptions.fromResults(
        buildArgParser().parse(['/some/project']),
      );
      expect(options.path, endsWith('some/project'));
    });

    test('unknown flag throws FormatException', () {
      expect(
        () => buildArgParser().parse(['--not-a-flag']),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
