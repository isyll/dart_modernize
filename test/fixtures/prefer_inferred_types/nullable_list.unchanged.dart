// Negative: declared type is nullable; Rule B requires non-nullable.
void f() {
  final List<String>? x = [];
  print(x);
}
