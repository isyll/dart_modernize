// Negative: the parameter is also read inside the constructor body, not only
// forwarded. A `super.id` parameter would change how it is referenced, so it is
// left as an explicit forward.
class Base {
  final int id;

  Base({required this.id});
}

class Derived extends Base {
  Derived({required int id}) : super(id: id) {
    print(id);
  }
}
