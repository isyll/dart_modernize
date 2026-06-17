// Negative: the body branches with an `if` before returning, so it is not a
// single return statement and cannot collapse to an `=>` body.
int sign(int x) {
  if (x < 0) {
    return -1;
  }
  return 1;
}
