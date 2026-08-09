// Negative: the loop variable is captured and written by a closure in the body,
// which the scan sees because it covers the whole loop, not just its statements.
void use(int value) {}

void loop(List<int> xs) {
  for (var x in xs) {
    void bump() {
      x = x + 1;
    }

    bump();
    use(x);
  }
}
