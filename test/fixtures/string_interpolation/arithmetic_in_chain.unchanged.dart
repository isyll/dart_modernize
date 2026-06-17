// Negative: the chain mixes string concatenation with an arithmetic `+` on ints
// (`a + b`) plus a `.toString()` method call. It is not a pure chain of
// String-typed, side-effect-free pieces, so it stays as written.
String label(int a, int b) {
  return 'sum=' + (a + b).toString();
}
