// Negative: the declared type is List<num> but the initializer produces
// List<int>. The type arguments differ, so removing the annotation would
// change the inferred type.
void main() {
  final List<num> l = <int>[1, 2, 3];
  print(l);
}
