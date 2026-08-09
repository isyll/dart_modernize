// Negative: an unrelated statement sits inside the run, so the declarations are
// not contiguous and collapsing them would move that statement's evaluation.
class Point {
  const Point(this.x, this.y);
  final int x;
  final int y;
}

Point getPoint() => const Point(1, 2);

int sum() {
  final p = getPoint();
  final x = p.x;
  print('between');
  final y = p.y;
  return x + y;
}
