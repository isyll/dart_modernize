// Negative: the local is reassigned partway through, so the later writes target
// a different object than the declaration's initializer. The run cannot collapse
// into a single cascade on the declared value.
class Paint {
  int color = 0;
  double strokeWidth = 0;
}

Paint make(int c) {
  var p = Paint();
  p.color = c;
  p = Paint();
  p.strokeWidth = 5.0;
  return p;
}
