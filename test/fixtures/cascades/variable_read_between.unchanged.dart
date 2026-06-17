// Negative: the target is read (`print(p.color)`) between writes. A cascade is a
// run of operations on one receiver; the intervening read makes the sequence
// observable, so it must not be folded.
class Paint {
  int color = 0;
  double strokeWidth = 0;
}

Paint make(int c) {
  var p = Paint();
  p.color = c;
  print(p.color);
  p.strokeWidth = 5.0;
  return p;
}
