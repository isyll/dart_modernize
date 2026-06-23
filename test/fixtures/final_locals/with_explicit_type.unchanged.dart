// Negative: the declaration uses an explicit type annotation, not var;
// final_locals only replaces the `var` keyword.
int compute() => 42;

int result() {
  int x = compute();
  return x;
}
