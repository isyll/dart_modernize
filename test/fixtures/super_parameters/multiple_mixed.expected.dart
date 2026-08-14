class Base {
  final int a;
  final int b;

  Base({required this.a, required this.b});
}

class Derived extends Base {
  final int c;

  Derived({required super.a, required super.b, required this.c});
}
