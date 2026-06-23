// Negative: an unrelated statement sits between the declaration and the return,
// so the return does not immediately follow the declaration.
int compute() => 42;
void doSomething() {}

int result() {
  final x = compute();
  doSomething();
  return x;
}
