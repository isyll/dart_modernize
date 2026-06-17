// Negative: the tested expression (`a`) differs from the spread source (`b`), so
// this is a genuine conditional spread, not a null-aware spread of `a`.
List<int> build(List<int>? a, List<int> b) {
  return [if (a != null) ...b];
}
