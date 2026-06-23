// Negative: x is read in a statement between the declaration and the return, so
// it is referenced in more than just the return position.
int compute() => 42;

int result(StringBuffer buf) {
  final x = compute();
  buf.write(x);
  return x;
}
