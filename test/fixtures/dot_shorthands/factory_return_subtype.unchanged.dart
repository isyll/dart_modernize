// Negative: a factory may return a subtype, so its `return` context is the
// declared class. A subtype constructor there stays qualified, because `.new()`
// would resolve against the super type and build the wrong object.
class Shape {
  const Shape();

  factory Shape.circle() => Circle();
}

class Circle extends Shape {
  const Circle();
}
