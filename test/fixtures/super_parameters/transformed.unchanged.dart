// Negative: the value is transformed (`id * 2`) before being forwarded, so it is
// not passed through unchanged. `super.id` forwards the parameter verbatim, so
// this must stay explicit.
class Base {
  final int id;

  Base({required this.id});
}

class Derived extends Base {
  Derived({required int id}) : super(id: id * 2);
}
