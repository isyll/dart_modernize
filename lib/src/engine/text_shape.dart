/// How the tool writes line endings back to files it edits.
///
///   * [auto] keeps each file's own dominant ending (the default).
///   * [lf] and [crlf] force one ending on every file the tool rewrites.
///
/// A UTF-8 BOM is always preserved regardless of this setting.
enum LineEndings { auto, lf, crlf }

/// The byte-level presentation of a text file that an edit must not disturb:
/// its dominant line ending and whether it opens with a UTF-8 BOM.
///
/// `dart format` (and, on older SDKs, `dart fix`) rewrite a file with LF
/// endings and drop a leading BOM. On a CRLF or BOM repository that turns a
/// one-line edit into a whole-file diff and silently loses the BOM. Recording
/// the shape from the original bytes and re-applying it after the edits keeps
/// the diff to the lines that actually changed.
final class TextShape {
  const TextShape({required this.hasBom, required this.usesCrlf});

  /// Detects the shape from a file's raw [bytes].
  ///
  /// Reads bytes rather than a decoded string on purpose: `readAsStringSync`
  /// silently drops a leading BOM, which is one of the things to detect. The
  /// dominant line ending is whichever of CRLF or bare LF occurs more often; a
  /// tie (including a file with no newlines) counts as LF.
  factory TextShape.ofBytes(List<int> bytes) {
    final hasBom =
        bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF;
    var crlf = 0;
    var lf = 0;
    for (var i = 0; i < bytes.length; i++) {
      if (bytes[i] == 0x0A) {
        if (i > 0 && bytes[i - 1] == 0x0D) {
          crlf++;
        } else {
          lf++;
        }
      }
    }
    return TextShape(hasBom: hasBom, usesCrlf: crlf > lf);
  }

  /// A leading UTF-8 byte-order mark as a Dart string (U+FEFF).
  static const _bom = '\u{FEFF}';

  /// Whether the file opens with a UTF-8 byte-order mark (`EF BB BF`).
  final bool hasBom;

  /// Whether the file's dominant line ending is CRLF rather than LF.
  final bool usesCrlf;

  /// Whether re-applying this shape in [LineEndings.auto] mode is a no-op for
  /// already-LF content: a plain LF file with no BOM needs no restoration.
  bool get isPlainLf => !hasBom && !usesCrlf;

  /// Rewrites [content] into this shape, forcing the line ending when [target]
  /// is not [LineEndings.auto].
  ///
  /// [content] may arrive with any endings (an edit can leave CRLF, `dart
  /// format` leaves LF), so it is normalized to LF first and then to the target
  /// ending. A BOM is added back only when the original file had one.
  String apply(String content, [LineEndings target = LineEndings.auto]) {
    var out = content.startsWith(_bom) ? content.substring(1) : content;
    out = out.replaceAll('\r\n', '\n');
    final crlf = switch (target) {
      LineEndings.auto => usesCrlf,
      LineEndings.crlf => true,
      LineEndings.lf => false,
    };
    if (crlf) out = out.replaceAll('\n', '\r\n');
    return hasBom ? '$_bom$out' : out;
  }

  @override
  bool operator ==(Object other) =>
      other is TextShape &&
      other.hasBom == hasBom &&
      other.usesCrlf == usesCrlf;

  @override
  int get hashCode => Object.hash(hasBom, usesCrlf);
}
