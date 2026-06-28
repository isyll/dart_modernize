/// Tests for the output/reporter layer.
///
/// The critical invariants:
///   - No-color mode emits zero ANSI codes.
///   - The diff lines written by [Reporter.renderDiff] are byte-identical
///     to the raw [unifiedDiff] output when color is disabled.
library;

import 'package:dart_modernize/src/engine/unified_diff.dart';
import 'package:dart_modernize/src/output/reporter.dart';
import 'package:test/test.dart';

void main() {
  group('no-color mode', () {
    test('renderDiff: no ANSI escape codes in output', () {
      final out = StringBuffer();
      final diffText = unifiedDiff(
        'a/foo.dart',
        'b/foo.dart',
        sampleBefore,
        sampleAfter,
      );
      makeNoColor(
        out: out,
      ).renderDiff('foo.dart', <String>['dot-shorthands'], 1, 1, diffText);
      expect(out.toString(), isNot(contains('\x1b[')));
    });

    test('renderDiff: diff lines are byte-identical to unifiedDiff output', () {
      final out = StringBuffer();
      final diffText = unifiedDiff(
        'a/foo.dart',
        'b/foo.dart',
        sampleBefore,
        sampleAfter,
      );
      makeNoColor(out: out).renderDiff('foo.dart', <String>[], 1, 1, diffText);
      final captured = out.toString();
      for (final line in diffText.split('\n').where((l) => l.isNotEmpty)) {
        expect(
          captured,
          contains(line),
          reason: 'diff line "$line" must appear unchanged in no-color output',
        );
      }
    });

    test('dryRunSummary: no ANSI codes', () {
      final out = StringBuffer();
      makeNoColor(out: out).dryRunSummary(
        scanned: 10,
        changed: 3,
        added: 5,
        removed: 2,
        passCounts: {'dot-shorthands': 2, 'expression-bodies': 1},
      );
      expect(out.toString(), isNot(contains('\x1b[')));
    });

    test('dryRunSummary: shows file counts and pass names', () {
      final out = StringBuffer();
      makeNoColor(out: out).dryRunSummary(
        scanned: 10,
        changed: 3,
        added: 5,
        removed: 2,
        passCounts: {'dot-shorthands': 2, 'expression-bodies': 1},
      );
      final text = out.toString();
      expect(text, contains('3 of 10'));
      expect(text, contains('nothing written'));
      expect(text, contains('+5'));
      expect(text, contains('-2'));
      expect(text, contains('dot-shorthands'));
      expect(text, contains('expression-bodies'));
    });

    test('completionSummary: shows totals and per-pass file counts', () {
      final out = StringBuffer();
      makeNoColor(out: out).completionSummary(
        scanned: 10,
        changed: 3,
        passCounts: {'dot-shorthands': 2, 'organize-imports': 1},
      );
      final text = out.toString();
      expect(text, isNot(contains('\x1b[')));
      expect(text, contains('Modernized 3 of 10'));
      expect(text, contains('dot-shorthands'));
      expect(text, contains('organize-imports'));
    });

    test('completionSummary: no changes prints an "already modern" line', () {
      final out = StringBuffer();
      makeNoColor(
        out: out,
      ).completionSummary(scanned: 7, changed: 0, passCounts: const {});
      final text = out.toString();
      expect(text, contains('Already modern'));
      expect(text, contains('7 file(s) scanned'));
    });

    test('error: no ANSI codes', () {
      final err = StringBuffer();
      makeNoColor(err: err).error('something went wrong');
      expect(err.toString(), isNot(contains('\x1b[')));
      expect(err.toString(), contains('Error: something went wrong'));
    });

    test('status methods: no ANSI codes', () {
      final out = StringBuffer();
      makeNoColor(out: out)
        ..validated()
        ..nothingToDo()
        ..resolving()
        ..finalizing()
        ..finalizingStep('dart format');
      expect(out.toString(), isNot(contains('\x1b[')));
    });
  });

  group('color mode', () {
    test('renderDiff: diff content preserved after stripping ANSI codes', () {
      final out = StringBuffer();
      final diffText = unifiedDiff(
        'a/foo.dart',
        'b/foo.dart',
        sampleBefore,
        sampleAfter,
      );
      makeWithColor(
        out: out,
      ).renderDiff('foo.dart', <String>[], 1, 1, diffText);
      final plain = out.toString().replaceAll(RegExp(r'\x1b\[[0-9;]*m'), '');
      for (final line in diffText.split('\n').where((l) => l.isNotEmpty)) {
        expect(plain, contains(line));
      }
    });
  });

  group('resolveColor', () {
    test(
      '--no-color flag returns false',
      () => expect(resolveColor(colorFlag: false), isFalse),
    );

    test(
      '--color flag returns true',
      () => expect(resolveColor(colorFlag: true), isTrue),
    );
  });
}

const sampleAfter = 'line1\nnew line\nline3\n';

const sampleBefore = 'line1\nold line\nline3\n';

Reporter makeNoColor({StringSink? out, StringSink? err}) =>
    .new(color: false, verbose: false, out: out, err: err);

Reporter makeWithColor({StringSink? out, StringSink? err}) =>
    .new(color: true, verbose: false, out: out, err: err);
