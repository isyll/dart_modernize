/// Generic classes, bounded type parameters, and generic methods.
class Box<T> {
  final T value;

  const Box(this.value);

  Box<R> map<R>(R Function(T) f) => Box(f(value));
}

T firstWhere<T>(List<T> items, bool Function(T) test, T fallback) {
  for (final item in items) {
    if (test(item)) return item;
  }
  return fallback;
}

num sumOf<T extends num>(List<T> values) {
  num total = 0;
  for (final v in values) {
    total += v;
  }
  return total;
}
