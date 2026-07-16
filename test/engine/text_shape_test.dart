/// Unit spec for [TextShape]: detecting a file's line-ending and BOM shape
/// from its bytes and re-applying it to edited content.
library;

import 'dart:convert';

import 'package:dart_modernize/src/engine/text_shape.dart';
import 'package:test/test.dart';

/// The three UTF-8 BOM bytes.
const _bomBytes = [0xEF, 0xBB, 0xBF];

/// A leading BOM as a string (U+FEFF).
const _bom = '\u{FEFF}';

List<int> _bytes(String s) => utf8.encode(s);

void main() {
  group('TextShape.ofBytes', () {
    test('plain LF file has no BOM and no CRLF', () {
      final shape = TextShape.ofBytes(_bytes('a\nb\nc\n'));
      expect(shape.hasBom, isFalse);
      expect(shape.usesCrlf, isFalse);
      expect(shape.isPlainLf, isTrue);
    });

    test('CRLF file is detected as CRLF', () {
      final shape = TextShape.ofBytes(_bytes('a\r\nb\r\n'));
      expect(shape.usesCrlf, isTrue);
      expect(shape.isPlainLf, isFalse);
    });

    test('a leading BOM is detected', () {
      final shape = TextShape.ofBytes([..._bomBytes, ..._bytes('a\nb\n')]);
      expect(shape.hasBom, isTrue);
      expect(shape.usesCrlf, isFalse);
      expect(shape.isPlainLf, isFalse);
    });

    test('BOM and CRLF are detected together', () {
      final shape = TextShape.ofBytes([..._bomBytes, ..._bytes('a\r\nb\r\n')]);
      expect(shape.hasBom, isTrue);
      expect(shape.usesCrlf, isTrue);
    });

    test('the dominant ending wins in a mixed file', () {
      expect(TextShape.ofBytes(_bytes('a\r\nb\r\nc\n')).usesCrlf, isTrue);
      expect(TextShape.ofBytes(_bytes('a\nb\nc\r\n')).usesCrlf, isFalse);
    });

    test('a tie counts as LF', () {
      expect(TextShape.ofBytes(_bytes('a\r\nb\n')).usesCrlf, isFalse);
    });

    test('a file with no newlines counts as LF', () {
      final shape = TextShape.ofBytes(_bytes('single line'));
      expect(shape.usesCrlf, isFalse);
      expect(shape.isPlainLf, isTrue);
    });

    test('fewer than three bytes cannot be a BOM', () {
      expect(TextShape.ofBytes([0xEF, 0xBB]).hasBom, isFalse);
      expect(TextShape.ofBytes(const []).hasBom, isFalse);
    });
  });

  group('TextShape.apply (auto)', () {
    test('LF content is rewritten with CRLF for a CRLF file', () {
      const shape = TextShape(hasBom: false, usesCrlf: true);
      expect(shape.apply('a\nb\n'), 'a\r\nb\r\n');
    });

    test('CRLF content is normalized to LF for an LF file', () {
      const shape = TextShape(hasBom: false, usesCrlf: false);
      expect(shape.apply('a\r\nb\r\n'), 'a\nb\n');
    });

    test('a BOM is added back for a BOM file', () {
      const shape = TextShape(hasBom: true, usesCrlf: false);
      expect(shape.apply('a\nb\n'), '${_bom}a\nb\n');
    });

    test('an existing leading BOM is not doubled', () {
      const shape = TextShape(hasBom: true, usesCrlf: false);
      expect(shape.apply('${_bom}a\n'), '${_bom}a\n');
    });

    test('a plain-LF file leaves already-LF content untouched', () {
      const shape = TextShape(hasBom: false, usesCrlf: false);
      expect(shape.apply('a\nb\n'), 'a\nb\n');
    });
  });

  group('TextShape.apply (forced)', () {
    test('crlf forces CRLF even for an LF file', () {
      const shape = TextShape(hasBom: false, usesCrlf: false);
      expect(shape.apply('a\nb\n', LineEndings.crlf), 'a\r\nb\r\n');
    });

    test('lf forces LF even for a CRLF file', () {
      const shape = TextShape(hasBom: false, usesCrlf: true);
      expect(shape.apply('a\r\nb\r\n', LineEndings.lf), 'a\nb\n');
    });

    test('a BOM is preserved regardless of the forced ending', () {
      const shape = TextShape(hasBom: true, usesCrlf: true);
      expect(shape.apply('a\r\nb\r\n', LineEndings.lf), '${_bom}a\nb\n');
    });
  });

  group('equality', () {
    test('shapes with the same fields are equal', () {
      expect(
        const TextShape(hasBom: true, usesCrlf: true),
        const TextShape(hasBom: true, usesCrlf: true),
      );
    });

    test('shapes differing in a field are not equal', () {
      expect(
        const TextShape(hasBom: true, usesCrlf: false),
        isNot(const TextShape(hasBom: false, usesCrlf: false)),
      );
    });
  });
}
