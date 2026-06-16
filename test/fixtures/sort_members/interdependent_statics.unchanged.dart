// Negative: members are already in canonical order, and the static fields are
// interdependent (`_b` reads `_a`). Sorting must keep within-kind order stable
// so initialization order is never broken.
class Registry {
  static final int _a = 1;
  static final int _b = _a + 1;

  static int get total => _a + _b;
}
