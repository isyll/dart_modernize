class Point {
  const Point(this.x, this.y, this.label);
  final int x;
  final int y;
  final String label;
}

void render(List<Point> points) {
  for (final Point(:x, :y) in points) {
    print(x + y);
  }
}
