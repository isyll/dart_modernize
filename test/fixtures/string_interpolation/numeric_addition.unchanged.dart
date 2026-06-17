// Negative: `+` here is integer addition, not string concatenation. The
// operands are not String-typed, so there is no interpolation to form.
int total(int a, int b) {
  return a + b;
}
