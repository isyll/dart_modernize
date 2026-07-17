import 'package:dart_modernize/dart_modernize.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('buildArgParser / CliOptions', () {
    test('all transformations are enabled by default', () {
      final options = CliOptions.fromResults(buildArgParser().parse([]));

      expect(options.dryRun, isFalse);
      expect(options.dotShorthands, isTrue);
      expect(options.privateNamedParameters, isTrue);
      expect(options.primaryConstructors, isTrue);
      expect(options.switchExpressions, isTrue);
      expect(options.cascades, isTrue);
      expect(options.expressionBodies, isTrue);
      expect(options.stringInterpolation, isTrue);
      expect(options.nullAwareSpread, isTrue);
      expect(options.nullAwareElements, isTrue);
      expect(options.organizeImports, isTrue);
      expect(options.sortMembers, isTrue);
      expect(options.fixAll, isTrue);
    });

    test('--no-switch-expressions disables only that transformation', () {
      final options = CliOptions.fromResults(
        buildArgParser().parse(['--no-switch-expressions']),
      );
      expect(options.switchExpressions, isFalse);
      // others unaffected
      expect(options.dotShorthands, isTrue);
      expect(options.primaryConstructors, isTrue);
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

    test('check is off by default', () {
      final options = CliOptions.fromResults(buildArgParser().parse([]));
      expect(options.check, isFalse);
    });

    test('--check enables check mode', () {
      final options = CliOptions.fromResults(
        buildArgParser().parse(['--check']),
      );
      expect(options.check, isTrue);
    });

    test('verify is enabled by default', () {
      final options = CliOptions.fromResults(buildArgParser().parse([]));
      expect(options.verify, isTrue);
    });

    test('--no-verify disables verification', () {
      final options = CliOptions.fromResults(
        buildArgParser().parse(['--no-verify']),
      );
      expect(options.verify, isFalse);
    });

    test('allow-dirty is off by default', () {
      final options = CliOptions.fromResults(buildArgParser().parse([]));
      expect(options.allowDirty, isFalse);
    });

    test('--allow-dirty enables it', () {
      final options = CliOptions.fromResults(
        buildArgParser().parse(['--allow-dirty']),
      );
      expect(options.allowDirty, isTrue);
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

    test('positional path is captured, made absolute, and normalized', () {
      final options = CliOptions.fromResults(
        buildArgParser().parse(['sub/project']),
      );
      expect(p.isAbsolute(options.path), isTrue);
      expect(options.path, endsWith(p.join('sub', 'project')));
      // The analyzer rejects mixed separators (e.g. `C:/proj` on Windows), so
      // normalization must leave only the platform separator behind.
      if (p.separator == r'\') {
        expect(options.path, isNot(contains('/')));
      }
    });

    test('--no-cascades disables only that transformation', () {
      final options = CliOptions.fromResults(
        buildArgParser().parse(['--no-cascades']),
      );
      expect(options.cascades, isFalse);
      expect(options.expressionBodies, isTrue);
      expect(options.dotShorthands, isTrue);
    });

    test('--no-string-interpolation disables only that transformation', () {
      final options = CliOptions.fromResults(
        buildArgParser().parse(['--no-string-interpolation']),
      );
      expect(options.stringInterpolation, isFalse);
      expect(options.cascades, isTrue);
      expect(options.nullAwareSpread, isTrue);
    });

    test('--no-null-aware-spread disables only that transformation', () {
      final options = CliOptions.fromResults(
        buildArgParser().parse(['--no-null-aware-spread']),
      );
      expect(options.nullAwareSpread, isFalse);
      expect(options.stringInterpolation, isTrue);
      expect(options.nullAwareElements, isTrue);
    });

    test('--no-null-aware-elements disables only that transformation', () {
      final options = CliOptions.fromResults(
        buildArgParser().parse(['--no-null-aware-elements']),
      );
      expect(options.nullAwareElements, isFalse);
      expect(options.nullAwareSpread, isTrue);
      expect(options.organizeImports, isTrue);
    });

    test('line endings default to auto', () {
      final options = CliOptions.fromResults(buildArgParser().parse([]));
      expect(options.lineEndings, LineEndings.auto);
    });

    test('--line-endings=lf and =crlf are parsed', () {
      expect(
        CliOptions.fromResults(
          buildArgParser().parse(['--line-endings=lf']),
        ).lineEndings,
        LineEndings.lf,
      );
      expect(
        CliOptions.fromResults(
          buildArgParser().parse(['--line-endings=crlf']),
        ).lineEndings,
        LineEndings.crlf,
      );
    });

    test('an invalid --line-endings value throws FormatException', () {
      expect(
        () => buildArgParser().parse(['--line-endings=mac']),
        throwsA(isA<FormatException>()),
      );
    });

    test('unknown flag throws FormatException', () {
      expect(
        () => buildArgParser().parse(['--not-a-flag']),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
