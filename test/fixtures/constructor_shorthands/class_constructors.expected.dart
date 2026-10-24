class Point {
  const new(this.x, this.y);
  const new origin() : x = 0, y = 0;
  new _internal(this.x) : y = 0;
  new copy(Point other) : this(other.x, other.y);

  factory fromJson(Map<String, Object?> json) =>
      Point(json['x'] as int, json['y'] as int);

  final int x;
  final int y;

  Point mirror() => Point._internal(-x);
}
