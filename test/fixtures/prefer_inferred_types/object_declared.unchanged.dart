// Negative: declared type is Object; relocating would change the type.
void f() {
  final Object o = [];
  print(o);
}
