class Vector {
  final double x;

  final double y;

  double get magnitude => x + y;

  Vector(this.x, this.y);

  void scale() {}

  Vector.zero() : this(0, 0);

  factory Vector.diagonal(double d) => Vector(d, d);
}
