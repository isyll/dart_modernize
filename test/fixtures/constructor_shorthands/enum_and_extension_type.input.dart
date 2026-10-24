enum Level {
  low(1),
  high(2);

  const Level(this.value);

  final int value;
}

extension type Id(int value) {
  Id.zero() : this(0);
}

mixin class Tracked {
  Tracked();
}
