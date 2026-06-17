/// Pattern matching: if-case with a guard, list patterns, and destructuring.
String describe(Object value) {
  if (value case int n when n > 0) {
    return 'positive int $n';
  }
  if (value case [final first, ...]) {
    return 'list starting with $first';
  }
  return 'other';
}

int firstOrZero(List<int> xs) {
  return switch (xs) {
    [] => 0,
    [final x, ...] => x,
  };
}
