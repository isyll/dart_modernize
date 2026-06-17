// Negative: a map lookup is not a stable simple reference. Reading it twice
// (test then value) could observe different results if the map is mutated, so
// it must not collapse to a single-evaluation null-aware element.
List<int> build(Map<String, int> m) {
  return [if (m['k'] != null) m['k']!];
}
