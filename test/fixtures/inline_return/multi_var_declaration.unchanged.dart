// Negative: the declaration introduces more than one variable, so there is no
// single initializer expression to lift into the return.
int result() {
  final a = 1, b = 2;
  return a;
}
