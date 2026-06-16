// Negative: the constructor forwards arguments to a superclass. A simple
// primary-constructor header cannot express this `super(...)` call, so the
// class is left untouched.
class Base {
  final int id;

  Base(this.id);
}

class Derived extends Base {
  final String label;

  Derived(this.label) : super(0);
}
