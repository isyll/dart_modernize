class Paint {
  int color = 0;
  double strokeWidth = 0;
}

Paint make(int c) {
  var p = Paint();
  p.color = c;
  p.strokeWidth = 5.0;
  return p;
}
