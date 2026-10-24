enum Planet {
  mercury(3.3),
  venus(4.8);

  const Planet(this.mass);

  final double mass;
}

enum Level {
  low(1),
  high(2);

  const Level(this.value);

  final int value;

  bool get isHigh => value > 1;
}
