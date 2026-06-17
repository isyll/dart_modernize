// Negative: the conditional spread has an `else` branch, so it always
// contributes elements. `...?a` contributes nothing when null, dropping the
// fallback, so the behaviour differs.
List<int> build(List<int>? a, List<int> fallback) {
  return [if (a != null) ...a else ...fallback];
}
