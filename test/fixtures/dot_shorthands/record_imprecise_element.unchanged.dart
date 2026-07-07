// Negative: the inferred record element type has a dynamic field, so the list
// is neither hoisted nor are its fields shortened; a bare `.a` would have no
// element type to resolve against.
enum E { a, b }

dynamic anything() => 1;

void demo() {
  final rows = [(E.a, anything())];
  print(rows);
}
