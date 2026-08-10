// The run stops at the call that reads the collection while building it: a
// literal cannot express that, so it stays a statement. Everything before it
// still folds.
List<int> build() {
  final items = <int>[1];
  items.add(items.length);
  return items;
}
