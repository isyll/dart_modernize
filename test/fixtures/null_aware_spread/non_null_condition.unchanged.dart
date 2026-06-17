// Negative: the spread is guarded by a boolean flag, not a `!= null` check. A
// null-aware spread only models the null guard, so this conditional must stay.
List<int> build(bool include, List<int> items) {
  return [if (include) ...items];
}
