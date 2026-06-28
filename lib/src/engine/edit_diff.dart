/// Turns a fully rewritten source string back into a single [SourceEdit].
///
/// The import organizer and member sorter rebuild the whole file as a new
/// string. [computeSimpleDiff] compares it against the original and returns one
/// edit covering only the part that changed.
library;

import 'source_edit.dart';

/// Returns the single edit that turns [oldStr] into [newStr], or null if equal.
SourceEdit? computeSimpleDiff(String oldStr, String newStr) {
  if (oldStr == newStr) return null;
  var prefixLength = findCommonPrefix(oldStr, newStr);
  final suffixLength = findCommonSuffix(oldStr, newStr);
  while (prefixLength >= 0) {
    final oldReplaceLength = oldStr.length - prefixLength - suffixLength;
    final newReplaceLength = newStr.length - prefixLength - suffixLength;
    if (oldReplaceLength >= 0 && newReplaceLength >= 0) {
      return .new(
        offset: prefixLength,
        length: oldReplaceLength,
        replacement: newStr.substring(
          prefixLength,
          newStr.length - suffixLength,
        ),
      );
    }
    prefixLength--;
  }
  return .new(offset: 0, length: oldStr.length, replacement: newStr);
}

/// Number of characters common to the start of [a] and [b].
int findCommonPrefix(String a, String b) {
  final n = a.length < b.length ? a.length : b.length;
  for (var i = 0; i < n; i++) {
    if (a.codeUnitAt(i) != b.codeUnitAt(i)) return i;
  }
  return n;
}

/// Number of characters common to the end of [a] and [b].
int findCommonSuffix(String a, String b) {
  final aLength = a.length;
  final bLength = b.length;
  final n = aLength < bLength ? aLength : bLength;
  for (var i = 1; i <= n; i++) {
    if (a.codeUnitAt(aLength - i) != b.codeUnitAt(bLength - i)) return i - 1;
  }
  return n;
}
