// Negative: the tested expression (`a`) differs from the produced value (`b`),
// so this is genuinely conditional, not a null-aware element.
List<int> build(int? a, int b) {
  return [if (a != null) b];
}
