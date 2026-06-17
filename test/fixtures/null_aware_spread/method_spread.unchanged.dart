// Negative: the spread source is a method call, which may have side effects and
// is evaluated twice in the if/spread form. `...?fetch()` evaluates once, so the
// rewrite is not behaviour-preserving.
List<int>? fetch() => const [1, 2];

List<int> build() {
  return [if (fetch() != null) ...fetch()!];
}
