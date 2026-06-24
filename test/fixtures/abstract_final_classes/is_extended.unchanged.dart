// Negative: the class is used as a superclass.
class Base {
  static const int version = 1;
}

class Derived extends Base {
  final int extra = 0;
}
