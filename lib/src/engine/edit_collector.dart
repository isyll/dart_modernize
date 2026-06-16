import 'source_edit.dart';

/// Accumulates [SourceEdit]s for a single file and applies them safely.
///
/// Edits are sorted by offset before application. Overlapping edits are
/// silently dropped — the earlier-offset edit wins.
final class EditCollector {
  final List<SourceEdit> _pending = [];

  bool get isEmpty => _pending.isEmpty;
  bool get isNotEmpty => _pending.isNotEmpty;

  /// Edits sorted by offset, with overlapping entries removed.
  List<SourceEdit> get resolved {
    final sorted = List.of(_pending)..sort();
    return _deoverlap(sorted);
  }

  void add(SourceEdit edit) => _pending.add(edit);

  void addAll(Iterable<SourceEdit> edits) => _pending.addAll(edits);

  /// Applies all collected edits to [source] and returns the modified string.
  String apply(String source) {
    final edits = resolved;
    if (edits.isEmpty) return source;

    final buffer = StringBuffer();
    var cursor = 0;
    for (final edit in edits) {
      buffer.write(source.substring(cursor, edit.offset));
      buffer.write(edit.replacement);
      cursor = edit.end;
    }
    buffer.write(source.substring(cursor));
    return buffer.toString();
  }

  void clear() => _pending.clear();

  static List<SourceEdit> _deoverlap(List<SourceEdit> sorted) {
    final result = <SourceEdit>[];
    for (final edit in sorted) {
      if (result.isEmpty || edit.offset >= result.last.end) {
        result.add(edit);
      }
    }
    return result;
  }
}
