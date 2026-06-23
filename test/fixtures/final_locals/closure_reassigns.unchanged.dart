// Negative: the variable is captured and reassigned inside a closure.
int makeCounter() {
  var x = 0;
  void inc() {
    x = x + 1;
  }
  inc();
  return x;
}
