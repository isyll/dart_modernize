import 'package:dart_modernize/dart_modernize.dart';
import 'package:test/test.dart';

void main() {
  group('SourceEdit', () {
    test('replaces the specified character range', () {
      const edit = SourceEdit(offset: 7, length: 5, replacement: 'Dart');
      expect(edit.apply('Hello, World!'), 'Hello, Dart!');
    });

    test('length 0 inserts without removing characters', () {
      const edit = SourceEdit(offset: 2, length: 0, replacement: 'X');
      expect(edit.apply('abcd'), 'abXcd');
    });

    test('length == source.length replaces entire string', () {
      const source = 'old';
      const edit = SourceEdit(offset: 0, length: 3, replacement: 'new');
      expect(edit.apply(source), 'new');
    });

    test('end == offset + length', () {
      const edit = SourceEdit(offset: 3, length: 4, replacement: '');
      expect(edit.end, 7);
    });

    test('compareTo orders edits by offset ascending', () {
      const a = SourceEdit(offset: 10, length: 1, replacement: '');
      const b = SourceEdit(offset: 5, length: 1, replacement: '');
      expect([a, b]..sort(), [b, a]);
    });
  });
}
