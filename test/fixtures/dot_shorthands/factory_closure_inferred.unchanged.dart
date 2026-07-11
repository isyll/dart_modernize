// Negative: `map` has no explicit `<T>`, so its element type is inferred from
// the closure body. Collapsing `Leaf(x)` to `.new(x)` would leave nothing to
// infer the type from, so the factory-closure body stays qualified.
class Leaf {
  Leaf(this.x);

  final int x;
}

void consume(List<int> xs) {
  xs.map((x) => Leaf(x)).toList();
}
