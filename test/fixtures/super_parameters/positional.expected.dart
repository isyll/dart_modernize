class Base {
  final int x;

  Base(this.x);
}

class Derived extends Base {
  Derived(super.x);
}
