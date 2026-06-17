class Base {
  final int a;
  final int b;

  Base({required this.a, required this.b});
}

class Derived extends Base {
  final int c;

  Derived({required int a, required int b, required this.c})
    : super(a: a, b: b);
}
