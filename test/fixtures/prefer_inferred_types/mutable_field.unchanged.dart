// Negative: mutable (non-final, non-const) fields are out of scope. Only
// final/const fields with an initializer have their annotation dropped.
class Box {
  String label = 'empty';
  int size = 0;
}
