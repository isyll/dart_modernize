/// Behavioural spec: generated files are never rewritten.
///
/// Codegen output (`*.g.dart`, `*.freezed.dart`, …) is owned by its generator;
/// rewriting it would be churn at best and corruption at worst. The pipeline
/// must skip those files while still processing hand-written sources alongside
/// them.
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
}

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
