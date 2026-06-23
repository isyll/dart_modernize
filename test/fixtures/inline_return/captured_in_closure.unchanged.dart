// Negative: x is captured by a closure that sits between the declaration and
// the return, so the local is referenced in more than just the return position.
int compute() => 42;

int result(List<int Function()> register) {
  final x = compute();
  register.add(() => x);
  return x;
}
