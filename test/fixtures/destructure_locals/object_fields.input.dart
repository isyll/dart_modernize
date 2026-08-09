class Point {
  const Point(this.x, this.y);
  final int x;
  final int y;
}

Point getPoint() => const Point(1, 2);

int sum() {
  final p = getPoint();
  final x = p.x;
  final y = p.y;
  return x + y;
}
