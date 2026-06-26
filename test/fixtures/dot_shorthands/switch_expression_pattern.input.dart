enum Shape { circle, square, triangle }

String describe(Shape s) => switch (s) {
  Shape.circle => 'round',
  Shape.square || Shape.triangle => 'angular',
};
