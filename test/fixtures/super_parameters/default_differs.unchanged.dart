// Negative: the derived parameter has a different default (5) than the base
// parameter (0). Folding to `super.id` risks changing which default applies, so
// the explicit forward is preserved.
class Base {
  final int id;

  Base({this.id = 0});
}

class Derived extends Base {
  Derived({int id = 5}) : super(id: id);
}
