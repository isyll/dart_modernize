// Negative: the initializer [] has no explicit type arguments, so its
// element type is inferred from the declared type via downward inference.
// Removing the annotation would change the inferred type to List<dynamic>.
void main() {
  final List<String> items = [];
  print(items);
}
