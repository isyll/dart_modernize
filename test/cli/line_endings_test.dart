/// Behavioural spec for issue #12: a run preserves each file's original line
/// endings and BOM, so a one-line edit does not become a whole-file diff.
///
/// The tool reads, edits, and writes files, then runs `dart format`, which
/// normalizes to LF and drops a leading BOM. These tests drive the real CLI and
/// assert on the raw bytes left on disk (not the decoded string, which would
/// hide the BOM).
library;

import 'package:test/test.dart';

import '../support/cli_harness.dart';
import '../support/triggers.dart';

void main() {
  group('line endings and BOM are preserved', () {
    // expression-bodies collapses this to `int square(int x) => x * x;`.
    final crlf = expressionBodiesTrigger.replaceAll('\n', '\r\n');

    test('a CRLF file stays CRLF', () async {
      final result = await runCli(
        files: {'lib/a.dart': crlf},
        args: onlyFeatureArgs('expression_bodies'),
      );

      expect(result.exitCode, 0, reason: result.stderr);
      expect(result.read('lib/a.dart'), contains('=>'), reason: 'must edit');
      final bytes = result.readBytes('lib/a.dart');
      expect(_allCrlf(bytes), isTrue, reason: 'every line ending stays CRLF');
      expect(_hasBom(bytes), isFalse, reason: 'no BOM was there to add');
    });

    test('an LF file stays LF', () async {
      final result = await runCli(
        files: {'lib/a.dart': expressionBodiesTrigger},
        args: onlyFeatureArgs('expression_bodies'),
      );

      expect(result.exitCode, 0, reason: result.stderr);
      expect(result.read('lib/a.dart'), contains('=>'), reason: 'must edit');
      final bytes = result.readBytes('lib/a.dart');
      expect(
        _hasCr(bytes),
        isFalse,
        reason: 'no CR introduced into an LF file',
      );
      expect(_hasBom(bytes), isFalse, reason: 'no BOM introduced');
    });

    test('a BOM is preserved', () async {
      final result = await runCli(
        files: {'lib/a.dart': '$_bom$expressionBodiesTrigger'},
        args: onlyFeatureArgs('expression_bodies'),
      );

      expect(result.exitCode, 0, reason: result.stderr);
      expect(result.read('lib/a.dart'), contains('=>'), reason: 'must edit');
      expect(
        _hasBom(result.readBytes('lib/a.dart')),
        isTrue,
        reason: 'dart format drops the BOM; the tool must put it back',
      );
    });

    test('a BOM and CRLF are preserved together', () async {
      final result = await runCli(
        files: {'lib/a.dart': '$_bom$crlf'},
        args: onlyFeatureArgs('expression_bodies'),
      );

      expect(result.exitCode, 0, reason: result.stderr);
      final bytes = result.readBytes('lib/a.dart');
      expect(_hasBom(bytes), isTrue, reason: 'BOM preserved');
      expect(_allCrlf(bytes), isTrue, reason: 'CRLF preserved');
    });

    test('rerunning on a CRLF file changes nothing', () async {
      final project = createProject(files: {'lib/a.dart': crlf});
      final first = await invokeCli(
        project,
        args: onlyFeatureArgs('expression_bodies'),
      );
      expect(first.exitCode, 0, reason: first.stderr);
      final afterFirst = first.readBytes('lib/a.dart');

      final second = await invokeCli(
        project,
        args: onlyFeatureArgs('expression_bodies'),
      );
      expect(second.exitCode, 0, reason: second.stderr);
      expect(
        second.readBytes('lib/a.dart'),
        afterFirst,
        reason: 'a second run must leave the CRLF file byte for byte identical',
      );
    });
  });

  group('--line-endings overrides the file default', () {
    final crlf = expressionBodiesTrigger.replaceAll('\n', '\r\n');

    test('lf forces LF on a CRLF file but keeps the BOM', () async {
      final result = await runCli(
        files: {'lib/a.dart': '$_bom$crlf'},
        args: [...onlyFeatureArgs('expression_bodies'), '--line-endings=lf'],
      );

      expect(result.exitCode, 0, reason: result.stderr);
      final bytes = result.readBytes('lib/a.dart');
      expect(_hasCr(bytes), isFalse, reason: 'lf forces LF endings');
      expect(_hasBom(bytes), isTrue, reason: 'BOM is preserved regardless');
    });

    test('crlf forces CRLF on an LF file', () async {
      final result = await runCli(
        files: {'lib/a.dart': expressionBodiesTrigger},
        args: [...onlyFeatureArgs('expression_bodies'), '--line-endings=crlf'],
      );

      expect(result.exitCode, 0, reason: result.stderr);
      final bytes = result.readBytes('lib/a.dart');
      expect(_allCrlf(bytes), isTrue, reason: 'crlf forces CRLF endings');
    });
  });
}

/// A leading BOM as a string, for building fixture content.
const _bom = '\u{FEFF}';

/// Whether every LF byte is part of a CRLF pair.
bool _allCrlf(List<int> b) {
  for (var i = 0; i < b.length; i++) {
    if (b[i] == 0x0A && (i == 0 || b[i - 1] != 0x0D)) return false;
  }
  return true;
}

bool _hasBom(List<int> b) =>
    b.length >= 3 && b[0] == 0xEF && b[1] == 0xBB && b[2] == 0xBF;

bool _hasCr(List<int> b) => b.contains(0x0D);
