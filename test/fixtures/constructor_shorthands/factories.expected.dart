abstract class Shape {
  const new();

  const factory circle(double r) = Circle;

  factory(String kind) => kind == 'circle' ? Circle(1) : const Square();
}

class Circle extends Shape {
  const new(this.r);

  final double r;
}

class Square extends Shape {
  const new();
}
