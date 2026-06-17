// Negative: the target is a parameter, not a freshly declared local with an
// initializer. There is no `var p = ...` for the writes to attach to, so this
// stays a plain sequence of statements.
class Paint {
  int color = 0;
  double strokeWidth = 0;
}

void configure(Paint p, int c) {
  p.color = c;
  p.strokeWidth = 5.0;
}
