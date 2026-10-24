abstract class Shape {
  const Shape();

  const factory Shape.circle(double r) = Circle;

  factory Shape(String kind) => kind == 'circle' ? Circle(1) : const Square();
}

class Circle extends Shape {
  const Circle(this.r);

  final double r;
}

class Square extends Shape {
  const Square.new();
}
