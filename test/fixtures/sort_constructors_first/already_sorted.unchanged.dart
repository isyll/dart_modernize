// Negative: constructors already appear before all other members.
class Point {
  Point(this.x, this.y);

  final int x;
  final int y;

  double distanceTo(Point other) => 0;
}
