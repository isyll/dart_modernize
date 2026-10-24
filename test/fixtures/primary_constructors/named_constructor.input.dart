class Vec {
  final int x;
  final int y;

  const Vec._(this.x, this.y);

  factory Vec.zero() => const Vec._(0, 0);
}

class Celsius {
  final double degrees;

  Celsius.new(this.degrees);
}
