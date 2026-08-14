abstract class Shape {
  factory Shape.circle(double r) = Circle;

  const Shape();

  factory Shape.square(double s) = Square;

  double get area;
}

class Circle extends Shape {
  const Circle(this.radius);

  final double radius;

  @override
  double get area => 3.14 * radius * radius;
}

class Square extends Shape {
  const Square(this.side);

  @override
  double get area => side * side;

  final double side;
}
