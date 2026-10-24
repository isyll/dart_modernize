// A negated or parenthesized integer literal in a `double` context is a
// double. Dropping the type would make each of these an `int`.
class Panel {
  static const double widthReduce = -20;
}

void f(double position) {
  double lastPosition = -1;
  lastPosition = position;
  final double half = (1);
  final double zero = -0;
  print('$lastPosition $half $zero');
}
