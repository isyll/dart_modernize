enum Level {
  low(1),
  high(2);

  new(this.value);

  final int value;
}

extension type Id(int value) {
  new zero() : this(0);
}

mixin class Tracked {
  new();
}
