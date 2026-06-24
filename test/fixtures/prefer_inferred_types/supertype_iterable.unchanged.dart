// Negative: declared type is Iterable, not List; relocating would change the type.
void f() {
  final Iterable<String> x = [];
  print(x);
}
