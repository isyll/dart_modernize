// Negative: the writes target two different objects, so they are not an
// uninterrupted run of member writes on a single receiver.
class Paint {
  int color = 0;
}

(Paint, Paint) make(int c) {
  var p = Paint();
  var q = Paint();
  p.color = c;
  q.color = c;
  return (p, q);
}
