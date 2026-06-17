// Negative: the body contains a comment that documents the return. Converting
// to an `=>` body would discard it, so the block body is preserved.
int magic(int x) {
  // Multiply by the answer to everything.
  return x * 42;
}
