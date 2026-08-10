// Negative: the loop variable is passed whole as well as read for a field, so
// the pattern would leave nothing to name it by.
class Point {
  const Point(this.x, this.y);
  final int x;
  final int y;
}

void draw(Point p) {}

void render(List<Point> points) {
  for (final point in points) {
    draw(point);
    print(point.x);
  }
}
