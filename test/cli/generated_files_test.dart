/// Behavioural spec: generated files are never rewritten.
///
/// Codegen output (`*.g.dart`, `*.freezed.dart`, …) is owned by its generator;
/// rewriting it would be churn at best and corruption at worst. The pipeline
/// must skip those files while still processing hand-written sources alongside
/// them. Beyond the known suffixes, two more signals mark generated code:
/// localization output declared in `l10n.yaml`, and a generated-code marker in
/// the file's leading comment block.
library;

import 'package:test/test.dart';

import '../support/cli_harness.dart';
import '../support/triggers.dart';

void main() {
  group('generated files', () {
    test(
      '*.g.dart and *.freezed.dart are skipped; normal files are not',
      () async {
        final result = await runCli(
          files: {
            'lib/widget.dart': dotShorthandsTrigger,
            'lib/widget.g.dart': dotShorthandsTrigger,
            'lib/model.freezed.dart': dotShorthandsTrigger,
          },
          args: onlyFeatureArgs('dot_shorthands'),
        );

        expect(result.exitCode, 0, reason: result.stderr);

        expect(
          result.read('lib/widget.g.dart'),
          dotShorthandsTrigger,
          reason: 'a .g.dart file must be left untouched',
        );
        expect(
          result.read('lib/model.freezed.dart'),
          dotShorthandsTrigger,
          reason: 'a .freezed.dart file must be left untouched',
        );
        expect(
          result.read('lib/widget.dart'),
          isNot(dotShorthandsTrigger),
          reason: 'the hand-written file must still be modernized',
        );
      },
    );

    test('exclusion still holds with several passes enabled', () async {
      final result = await runCli(
        files: {
          'lib/widget.dart': _multiPass,
          'lib/widget.g.dart': _multiPass,
          'lib/model.freezed.dart': _multiPass,
        },
        args: onlyFeaturesArgs({
          'dot_shorthands',
          'super_parameters',
          'expression_bodies',
        }),
      );

      expect(result.exitCode, 0, reason: result.stderr);
      expect(
        result.read('lib/widget.g.dart'),
        _multiPass,
        reason: 'a .g.dart file must be untouched by every pass',
      );
      expect(
        result.read('lib/model.freezed.dart'),
        _multiPass,
        reason: 'a .freezed.dart file must be untouched by every pass',
      );
      expect(
        result.read('lib/widget.dart'),
        isNot(_multiPass),
        reason: 'the hand-written file must still be modernized',
      );
    });
  });

  group('generated localization output', () {
    test(
      'gen-l10n default output is skipped when l10n.yaml is present',
      () async {
        final result = await runCli(
          files: {
            'lib/widget.dart': dotShorthandsTrigger,
            'lib/l10n/app_localizations.dart': dotShorthandsTrigger,
            'lib/l10n/app_localizations_fr.dart': dotShorthandsTrigger,
            'l10n.yaml':
                'arb-dir: lib/l10n\n'
                'template-arb-file: app_en.arb\n'
                'output-localization-file: app_localizations.dart\n',
          },
          args: onlyFeatureArgs('dot_shorthands'),
        );

        expect(result.exitCode, 0, reason: result.stderr);
        expect(
          result.read('lib/l10n/app_localizations.dart'),
          dotShorthandsTrigger,
          reason: 'the main localization file must be left untouched',
        );
        expect(
          result.read('lib/l10n/app_localizations_fr.dart'),
          dotShorthandsTrigger,
          reason: 'a per-locale localization file must be left untouched',
        );
        expect(
          result.read('lib/widget.dart'),
          isNot(dotShorthandsTrigger),
          reason: 'the hand-written file must still be modernized',
        );
      },
    );

    test(
      'custom output-dir and output-localization-file are honored',
      () async {
        final result = await runCli(
          files: {
            'lib/widget.dart': dotShorthandsTrigger,
            'lib/generated/i18n/l10n.dart': dotShorthandsTrigger,
            'lib/generated/i18n/l10n_es.dart': dotShorthandsTrigger,
            'l10n.yaml':
                'arb-dir: lib/i18n\n'
                'output-dir: lib/generated/i18n\n'
                'output-localization-file: l10n.dart\n',
          },
          args: onlyFeatureArgs('dot_shorthands'),
        );

        expect(result.exitCode, 0, reason: result.stderr);
        expect(
          result.read('lib/generated/i18n/l10n.dart'),
          dotShorthandsTrigger,
          reason: 'the custom localization file must be left untouched',
        );
        expect(
          result.read('lib/generated/i18n/l10n_es.dart'),
          dotShorthandsTrigger,
          reason: 'a per-locale custom localization file must be untouched',
        );
        expect(
          result.read('lib/widget.dart'),
          isNot(dotShorthandsTrigger),
          reason: 'the hand-written file must still be modernized',
        );
      },
    );

    test(
      'app_localizations.dart is processed when there is no l10n.yaml',
      () async {
        final result = await runCli(
          files: {'lib/l10n/app_localizations.dart': dotShorthandsTrigger},
          args: onlyFeatureArgs('dot_shorthands'),
        );

        expect(result.exitCode, 0, reason: result.stderr);
        expect(
          result.read('lib/l10n/app_localizations.dart'),
          isNot(dotShorthandsTrigger),
          reason:
              'without l10n.yaml the name is not proof of generation, so the '
              'file must be modernized like any hand-written source',
        );
      },
    );
  });

  group('generated-code header', () {
    test('a line-comment marker skips the file', () async {
      final result = await runCli(
        files: {
          'lib/widget.dart': dotShorthandsTrigger,
          'lib/api.dart': _lineHeader,
        },
        args: onlyFeatureArgs('dot_shorthands'),
      );

      expect(result.exitCode, 0, reason: result.stderr);
      expect(
        result.read('lib/api.dart'),
        _lineHeader,
        reason:
            'a file marked GENERATED CODE - DO NOT MODIFY must be untouched',
      );
      expect(
        result.read('lib/widget.dart'),
        isNot(dotShorthandsTrigger),
        reason: 'the hand-written file must still be modernized',
      );
    });

    test('a DO NOT EDIT block-comment marker skips the file', () async {
      final result = await runCli(
        files: {'lib/api.dart': _blockHeader},
        args: onlyFeatureArgs('dot_shorthands'),
      );

      expect(result.exitCode, 0, reason: result.stderr);
      expect(
        result.read('lib/api.dart'),
        _blockHeader,
        reason: 'a file marked DO NOT EDIT must be left untouched',
      );
    });

    test('an innocuous leading comment does not skip the file', () async {
      final result = await runCli(
        files: {'lib/api.dart': _innocuousHeader},
        args: onlyFeatureArgs('dot_shorthands'),
      );

      expect(result.exitCode, 0, reason: result.stderr);
      expect(
        result.read('lib/api.dart'),
        isNot(_innocuousHeader),
        reason:
            'a plain doc comment must not be mistaken for a generated marker',
      );
    });
  });
}

/// A dot-shorthands trigger behind a block-comment `DO NOT EDIT` marker.
const _blockHeader = '''
/*
 * DO NOT EDIT. This file is machine generated.
 */

E pick() => E.a;

enum E { a, b }
''';

/// A dot-shorthands trigger behind an ordinary hand-written comment.
const _innocuousHeader = '''
// A small helper library for picking a value.

E pick() => E.a;

enum E { a, b }
''';

/// A dot-shorthands trigger behind a line-comment generated marker.
const _lineHeader = '''
// GENERATED CODE - DO NOT MODIFY BY HAND

E pick() => E.a;

enum E { a, b }
''';

/// A file three implemented passes touch at once: dot-shorthands (`.fast`),
/// super-parameters (`super.id`), and expression-bodies (`square`).
const _multiPass = '''
enum Mode { fast, slow }

class Base {
  final int id;

  Base({required this.id});
}

class Worker extends Base {
  Worker({required int id}) : super(id: id);

  Mode mode() => Mode.fast;
}

int square(int x) {
  return x * x;
}
''';
