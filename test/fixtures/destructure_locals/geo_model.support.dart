class Point {
  const Point(this.x, this.y);

  final int x;
  final int y;
}

Point origin() => const Point(0, 0);

Point? find(int id) => id == 0 ? const Point(0, 0) : null;
