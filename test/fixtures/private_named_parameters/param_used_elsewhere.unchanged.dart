// Negative: the parameter `x` also initializes `_doubled`. Folding it into
// `this._x` removes the `x` name the second initializer still depends on.
class Pair {
  final int _x;
  final int _doubled;

  Pair({required int x}) : _x = x, _doubled = x * 2;
}
