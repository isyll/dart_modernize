// Negative: an unrelated statement interrupts the run of member writes, so the
// writes are not a contiguous sequence that can fold into one cascade.
class Paint {
  int color = 0;
  double strokeWidth = 0;
}

Paint make(int c, List<String> log) {
  var p = Paint();
  p.color = c;
  log.add('color set');
  p.strokeWidth = 5.0;
  return p;
}
