// Negative: the literal 3 is an integer literal whose static type is int.
// The declared type is double; dropping the annotation would change the
// inferred type from double to int.
void main() {
  final double d = 3;
  print(d);
}
