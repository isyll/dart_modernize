class Paint {
  int color = 0;
  double strokeWidth = 0;
}

Paint defaultPaint() => Paint();

Paint make(int c) {
  var p = defaultPaint();
  p.color = c;
  p.strokeWidth = 5.0;
  return p;
}
