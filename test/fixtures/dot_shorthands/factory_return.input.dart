class Counter {
  const Counter(this.value);

  final int value;

  factory Counter.zero() {
    return Counter(0);
  }

  factory Counter.of(int n) => Counter(n);
}
