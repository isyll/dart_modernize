/// Behavioural spec for `--only`, the allow-list that runs a chosen subset of
/// transformations and skips every other one.
///
/// Four layers are covered:
///   * parsing: `CliOptions.fromResults` maps `--only` names to exactly the
///     named passes (comma-separated or repeated), leaves the rest off, and
///     rejects an unknown name;
///   * disambiguation: a positional argument is *always* the target path, so a
///     bare word that happens to match a pass name (e.g. `cascades`) is the
///     path, never a selection;
///   * path handling: a selection and a path can be given together; and
///   * end-to-end: the CLI applies only the selected pass(es) to a project that
///     would otherwise trigger several, leaving the rest byte-for-byte intact.
library;

import 'package:dart_modernize/dart_modernize.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/cli_harness.dart';
import '../support/triggers.dart';

void main() {
  group('--only parsing', () {
    test('transformationNames matches every wired transformation flag', () {
      // The allow-list must line up with the harness feature map (one entry per
      // transformation), so a new pass cannot be added to one and forgotten in
      // the other.
      expect(transformationNames.toSet(), equals(featureFlags.values.toSet()));
      // Every getter in the fixture map is a real allow-list entry, and vice
      // versa: the two views of the pass set agree.
      expect(
        _enabledByName(_parse([])).keys.toSet(),
        equals(transformationNames.toSet()),
      );
    });

    test('a single name enables exactly that pass and disables the rest', () {
      final enabled = _enabledByName(_parse(['--only', 'dot-shorthands']));

      expect(enabled['dot-shorthands'], isTrue);
      for (final entry in enabled.entries) {
        if (entry.key == 'dot-shorthands') continue;
        expect(
          entry.value,
          isFalse,
          reason: '${entry.key} must be off when only dot-shorthands is named',
        );
      }
    });

    test('comma-separated names enable each named pass', () {
      final enabled = _enabledByName(_parse(['--only', 'cascades,fix-all']));
      expect(enabled['cascades'], isTrue);
      expect(enabled['fix-all'], isTrue);
      expect(enabled['dot-shorthands'], isFalse);
      expect(enabled['organize-imports'], isFalse);
    });

    test('a repeated --only enables each named pass', () {
      final enabled = _enabledByName(
        _parse(['--only', 'cascades', '--only', 'fix-all']),
      );
      expect(enabled['cascades'], isTrue);
      expect(enabled['fix-all'], isTrue);
      expect(enabled['dot-shorthands'], isFalse);
    });

    test('a --no-<name> switch subtracts from an --only set', () {
      // --no- always removes a pass, even one named by --only, so an explicit
      // contradiction leaves that pass off (and everything unnamed off too).
      final enabled = _enabledByName(
        _parse(['--only', 'cascades,fix-all', '--no-cascades']),
      );
      expect(enabled['cascades'], isFalse);
      expect(enabled['fix-all'], isTrue);
      expect(enabled['dot-shorthands'], isFalse);
    });

    test('every allow-listed name selects one pass and only that pass', () {
      for (final name in transformationNames) {
        final enabled = _enabledByName(_parse(['--only', name]));
        final on = enabled.entries.where((e) => e.value).map((e) => e.key);
        expect(on, equals([name]), reason: 'selecting $name');
      }
    });

    test('no --only leaves every pass at its default', () {
      // On by default, except the opt-in passes in defaultOffTransformations.
      final enabled = _enabledByName(_parse([]));
      for (final entry in enabled.entries) {
        expect(
          entry.value,
          !defaultOffTransformations.contains(entry.key),
          reason: '${entry.key} should be at its default',
        );
      }
    });

    test('an unknown --only name throws a FormatException', () {
      expect(() => _parse(['--only', 'not-a-pass']), throwsFormatException);
    });
  });

  group('positional path handling', () {
    test('a bare word matching a pass name is the path, not a selection', () {
      // The core disambiguation: `dart_modernize cascades` targets a directory
      // named `cascades`; it never selects the cascades pass. With no selection,
      // every pass stays at its default: cascades still on, opt-in sort-members
      // still off.
      final options = _parse(['cascades']);
      expect(options.path, endsWith('cascades'));
      final enabled = _enabledByName(options);
      expect(enabled['cascades'], isTrue);
      expect(enabled['sort-members'], isFalse);
    });

    test('a selection and a path can be given together', () {
      final options = _parse(['--only', 'cascades', 'sub/project']);
      final enabled = _enabledByName(options);
      expect(enabled['cascades'], isTrue);
      expect(enabled['fix-all'], isFalse);
      expect(p.isAbsolute(options.path), isTrue);
      expect(options.path, endsWith(p.join('sub', 'project')));
    });

    test('more than one target path throws a FormatException', () {
      expect(() => _parse(['sub/a', 'sub/b']), throwsFormatException);
    });
  });

  group('--only end-to-end', () {
    test(
      'applies only the named pass, leaving other triggers untouched',
      () async {
        final result = await runCli(
          files: {
            'lib/interp.dart': stringInterpolationTrigger,
            'lib/dot.dart': dotShorthandsTrigger,
          },
          args: ['--only', 'string-interpolation'],
        );

        expect(result.exitCode, 0, reason: result.stderr);
        // The selected pass fired.
        expect(
          result.read('lib/interp.dart'),
          isNot(stringInterpolationTrigger),
        );
        expect(result.read('lib/interp.dart'), contains(r'$name'));
        // Every other pass (including dot-shorthands and all finalize passes) was
        // skipped, so its trigger is byte-for-byte unchanged.
        expect(result.read('lib/dot.dart'), dotShorthandsTrigger);
      },
    );

    test('applies several passes when more than one is named', () async {
      final result = await runCli(
        files: {
          'lib/interp.dart': stringInterpolationTrigger,
          'lib/dot.dart': dotShorthandsTrigger,
          'lib/final.dart': finalLocalsTrigger,
        },
        args: ['--only', 'string-interpolation,dot-shorthands'],
      );

      expect(result.exitCode, 0, reason: result.stderr);
      expect(result.read('lib/interp.dart'), isNot(stringInterpolationTrigger));
      expect(result.read('lib/dot.dart'), isNot(dotShorthandsTrigger));
      expect(result.read('lib/dot.dart'), contains('=> .a'));
      // A pass that was not named is still skipped.
      expect(result.read('lib/final.dart'), finalLocalsTrigger);
    });

    test(
      'an unknown --only name exits 64 with an error and a help hint',
      () async {
        final result = await runCli(
          files: {'lib/a.dart': 'void f() {}\n'},
          args: ['--only', 'not-a-pass'],
        );

        expect(result.exitCode, 64);
        expect(result.stdout, isEmpty);
        expect(result.stderr, contains('Error:'));
        expect(result.stderr, contains('dart_modernize --help'));
        expect(result.read('lib/a.dart'), 'void f() {}\n');
      },
    );
  });
}

/// The enabled state of every transformation, keyed by its CLI flag name.
///
/// Lets a test assert over [transformationNames] without hard-coding each of
/// the eighteen boolean getters.
Map<String, bool> _enabledByName(CliOptions o) => {
  'dot-shorthands': o.dotShorthands,
  'private-named-parameters': o.privateNamedParameters,
  'primary-constructors': o.primaryConstructors,
  'super-parameters': o.superParameters,
  'switch-expressions': o.switchExpressions,
  'expression-bodies': o.expressionBodies,
  'organize-imports': o.organizeImports,
  'sort-members': o.sortMembers,
  'fix-all': o.fixAll,
  'cascades': o.cascades,
  'string-interpolation': o.stringInterpolation,
  'null-aware-spread': o.nullAwareSpread,
  'null-aware-elements': o.nullAwareElements,
  'inline-return': o.inlineReturn,
  'final-locals': o.finalLocals,
  'abstract-final-classes': o.abstractFinalClasses,
  'prefer-inferred-types': o.preferInferredTypes,
  'sort-constructors-first': o.sortConstructorsFirst,
};

CliOptions _parse(List<String> args) =>
    .fromResults(buildArgParser().parse(args));
