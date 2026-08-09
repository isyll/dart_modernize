// Negative: the chain is rooted at a different variable than the one the null
// test proved non-null, so collapsing it would drop the guard entirely.
class Box {
  String get name => 'n';
}

String mismatched(Box? box, Box other, String fallback) =>
    box != null ? other.name : fallback;
