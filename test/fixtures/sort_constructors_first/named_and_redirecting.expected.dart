class Vector {
  Vector(this.x, this.y);

  Vector.zero() : this(0, 0);

  factory Vector.diagonal(double d) => Vector(d, d);

  final double x;

  final double y;

  double get magnitude => x + y;

  void scale() {}
}
