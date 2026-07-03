abstract class Shape {
  double get area;

  factory Shape.circle(double r) = Circle;

  const Shape();

  factory Shape.square(double s) = Square;
}

class Circle extends Shape {
  final double radius;

  @override
  double get area => 3.14 * radius * radius;

  const Circle(this.radius);
}

class Square extends Shape {
  @override
  double get area => side * side;

  final double side;

  const Square(this.side);
}
