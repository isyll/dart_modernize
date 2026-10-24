class Point {
  const Point(this.x, this.y);
  const Point.origin() : x = 0, y = 0;
  Point._internal(this.x) : y = 0;
  Point.copy(Point other) : this(other.x, other.y);

  factory Point.fromJson(Map<String, Object?> json) =>
      Point(json['x'] as int, json['y'] as int);

  final int x;
  final int y;

  Point mirror() => Point._internal(-x);
}
