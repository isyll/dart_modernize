// Negative: the intermediate is also passed whole, so it cannot be removed.
class Point {
  const Point(this.x, this.y);
  final int x;
  final int y;
}

Point getPoint() => const Point(1, 2);
void draw(Point p) {}

int sum() {
  final p = getPoint();
  final x = p.x;
  draw(p);
  return x;
}
