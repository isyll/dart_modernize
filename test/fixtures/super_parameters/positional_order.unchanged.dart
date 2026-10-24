// The parameters are declared in the opposite order of the arguments they
// feed; `super.` positionals would be passed as (b, a).
class Base {
  Base(this.a, this.b);

  final int a;
  final int b;
}

class Swapped extends Base {
  Swapped(int b, int a) : super(a, b);
}
