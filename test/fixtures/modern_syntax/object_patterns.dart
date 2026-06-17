/// Object patterns destructuring fields inside switch arms.
class Point {
  final int x;
  final int y;

  const Point(this.x, this.y);

  const Point.origin() : this(0, 0);
}

String classify(Point p) {
  return switch (p) {
    Point(x: 0, y: 0) => 'origin',
    Point(x: final px, y: 0) => 'on x-axis at $px',
    Point(x: 0, y: final py) => 'on y-axis at $py',
    Point(x: final px, y: final py) => 'at ($px, $py)',
  };
}
