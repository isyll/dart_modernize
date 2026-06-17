// Negative: the collection-if has an `else` branch, so it always contributes an
// element. `?a` would contribute nothing when null, dropping the fallback, so
// the behaviour differs.
List<int> build(int? a) {
  return [if (a != null) a else 0];
}
