/// A sealed hierarchy with an exhaustive switch (no default needed).
sealed class Shape {
  const Shape();
}

final class Circle extends Shape {
  final double radius;

  const Circle(this.radius);
}

final class Square extends Shape {
  final double side;

  const Square(this.side);
}

double area(Shape shape) => switch (shape) {
  Circle(:final radius) => 3.14159 * radius * radius,
  Square(:final side) => side * side,
};
