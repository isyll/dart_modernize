// Negative: the local parameter (`code`) has a different name than the super
// parameter (`id`). Rewriting to `super.id` would rename the parameter and
// change this constructor's public API, so it must stay.
class Base {
  final int id;

  Base({required this.id});
}

class Derived extends Base {
  Derived({required int code}) : super(id: code);
}
