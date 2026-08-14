class Base {
  final int id;

  Base({required this.id});
}

class Derived extends Base {
  Derived({required super.id});
}
