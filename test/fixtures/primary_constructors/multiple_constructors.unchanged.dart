// Negative: a primary constructor cannot coexist with another non-redirecting
// generative constructor. This class has two, so it must stay as-is.
class Point {
  final int x;
  final int y;

  Point(this.x, this.y);

  Point.origin() : x = 0, y = 0;
}
