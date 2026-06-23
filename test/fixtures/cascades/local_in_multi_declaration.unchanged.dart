// Negative: the target is part of a multi-variable declaration; the cascade
// fold does not apply to declarations with more than one variable.
class Paint {
  int color = 0;
  double strokeWidth = 0;
}

void setup() {
  var p = Paint(), q = Paint();
  p.color = 1;
  p.strokeWidth = 2.0;
  q.color = 3;
}
