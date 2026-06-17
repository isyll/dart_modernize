// Negative: the target is passed as an argument mid-sequence, which can observe
// its partially-configured state. Folding into a cascade would move that call
// before the object is bound to the variable, changing behaviour.
class Paint {
  int color = 0;
  double strokeWidth = 0;
}

void register(Paint p) {}

Paint make(int c) {
  var p = Paint();
  p.color = c;
  register(p);
  p.strokeWidth = 5.0;
  return p;
}
