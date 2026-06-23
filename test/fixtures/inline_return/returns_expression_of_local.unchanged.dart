// Negative: the return expression involves the local rather than being a bare
// identifier, so there is no simple initializer to lift.
int f() => 10;

int result() {
  final x = f();
  return x + 1;
}
