// Already-modern code an earlier run can produce. Re-running must not break it:
// a dot-shorthand initializer keeps its declared type, and a generic
// constructor whose type is inferred from its arguments keeps those arguments.

class Box {
  const Box(this.width);

  final int width;
}

class Pair<T> {
  const Pair(this.first, this.second);

  final T first;
  final T second;
}

enum Mode { fast, slow }

class Defaults {
  static const Box unit = .new(1);
  static const Mode mode = .fast;
}

List<int> widths() {
  final pair = Pair(Box(1), Box(2));
  return [pair.first.width, pair.second.width];
}
