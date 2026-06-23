// Negative: a comment precedes the declaration and would be lost if the
// declaration line were removed.
int compute() => 42;

int result() {
  // Important: compute() may throw.
  final x = compute();
  return x;
}
