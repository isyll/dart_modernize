enum Planet(final double mass) {
  mercury(3.3),
  venus(4.8),
}

enum Level(final int value) {
  low(1),
  high(2);

  bool get isHigh => value > 1;
}
