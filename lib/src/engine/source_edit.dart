/// An immutable, positional edit to a Dart source file.
///
/// Edits must be non-overlapping. Use [EditCollector] to accumulate and apply
/// a set of edits safely.
final class SourceEdit implements Comparable<SourceEdit> {
  /// Zero-based character offset from the start of the file.
  final int offset;

  /// Number of characters to replace starting at [offset].
  final int length;

  /// Text to insert at [offset] in place of [length] characters.
  final String replacement;

  const SourceEdit({
    required this.offset,
    required this.length,
    required this.replacement,
  });

  /// One past the last replaced character.
  int get end => offset + length;

  /// Applies this edit to [source] and returns the result.
  String apply(String source) =>
      source.substring(0, offset) + replacement + source.substring(end);

  @override
  int compareTo(SourceEdit other) => offset.compareTo(other.offset);

  @override
  String toString() =>
      'SourceEdit(offset: $offset, length: $length, '
      'replacement: ${replacement.length} chars)';
}
