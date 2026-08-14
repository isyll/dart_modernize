class Counter {
  const Counter(this.value);

  final int value;

  factory Counter.zero() {
    return .new(0);
  }

  factory Counter.of(int n) => .new(n);
}
