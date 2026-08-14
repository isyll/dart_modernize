// Negative: a promoted field keeps only its type and name, so the doc comment
// would be deleted. The class is left alone instead.
class Point {
  /// Distance from the left edge.
  final int x;

  /// Distance from the top edge.
  final int y;

  Point(this.x, this.y);
}
