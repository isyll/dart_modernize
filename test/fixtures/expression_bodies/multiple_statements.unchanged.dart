// Negative: the body has more than one statement, so it cannot be expressed as
// a single `=>` expression.
int compute(int x) {
  final doubled = x * 2;
  return doubled + 1;
}
