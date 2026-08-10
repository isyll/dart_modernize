// Negative: the literal already holds an element, so folding the run in would
// have to reason about where the existing entries sit.
List<int> build() {
  final items = <int>[0];
  items.add(1);
  return items;
}
