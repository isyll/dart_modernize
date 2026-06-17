import 'package:dart_modernize/dart_modernize.dart';
import 'package:test/test.dart';

void main() {
  group('EditCollector', () {
    test('returns original string when no edits added', () {
      final collector = EditCollector();
      expect(collector.apply('unchanged'), 'unchanged');
    });

    test('applies a single edit', () {
      final collector = EditCollector()
        ..add(const .new(offset: 0, length: 5, replacement: 'Hi'));
      expect(collector.apply('Hello world'), 'Hi world');
    });

    test(
      'applies multiple non-overlapping edits regardless of insertion order',
      () {
        final collector = EditCollector()
          ..addAll([
            const .new(offset: 7, length: 5, replacement: 'Dart'),
            const .new(offset: 0, length: 5, replacement: 'Hi'),
          ]);
        expect(collector.apply('Hello, World!'), 'Hi, Dart!');
      },
    );

    test('overlapping edits: earlier-offset edit wins, later is dropped', () {
      final collector = EditCollector()
        ..addAll([
          const .new(offset: 0, length: 5, replacement: 'A'),
          const .new(offset: 2, length: 3, replacement: 'B'),
        ]);
      // 'B' starts inside 'A', so 'A' wins and 'B' is dropped.
      expect(collector.apply('Hello world'), 'A world');
    });

    test('isEmpty reflects whether edits have been added', () {
      final collector = EditCollector();
      expect(collector.isEmpty, isTrue);
      collector.add(const .new(offset: 0, length: 1, replacement: ''));
      expect(collector.isEmpty, isFalse);
    });

    test('clear removes all pending edits', () {
      final collector = EditCollector()
        ..add(const .new(offset: 0, length: 3, replacement: 'x'));
      collector.clear();
      expect(collector.isEmpty, isTrue);
      expect(collector.apply('abc'), 'abc');
    });

    test('resolved returns edits sorted by offset', () {
      final collector = EditCollector()
        ..addAll([
          const .new(offset: 10, length: 1, replacement: ''),
          const .new(offset: 2, length: 1, replacement: ''),
          const .new(offset: 6, length: 1, replacement: ''),
        ]);
      final offsets = collector.resolved.map((e) => e.offset).toList();
      expect(offsets, [2, 6, 10]);
    });
  });
}
