// Only part of the positional arguments can fold, so none of them do: a
// constructor cannot mix `super.` positionals with positional arguments. The
// named one still folds.
class Base {
  Base(this.a, this.b, {this.label});

  final int a;
  final int b;
  final String? label;
}

class Derived extends Base {
  Derived(int a, {super.label}) : super(a, 0);
}
