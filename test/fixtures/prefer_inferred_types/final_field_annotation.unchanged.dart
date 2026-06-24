// Negative: non-const class fields are out of scope. Effective Dart recommends
// annotating these, and their inferred type can depend on complex initializers
// or field promotion.
class Widget {
  final String label = 'default';
  final int count = 0;
}
