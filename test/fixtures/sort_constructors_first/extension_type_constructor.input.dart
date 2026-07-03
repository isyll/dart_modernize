extension type Meters(int value) {
  int get squared => value * value;

  bool get isZero => value == 0;

  Meters.zero() : this(0);
}
