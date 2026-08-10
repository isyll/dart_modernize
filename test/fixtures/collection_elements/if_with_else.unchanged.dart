// Negative: the `if` has an `else`, which is not the guard-only shape this pass
// folds.
List<String> build(bool flag, String a, String b) {
  final items = <String>[];
  if (flag) {
    items.add(a);
  } else {
    items.add(b);
  }
  return items;
}
