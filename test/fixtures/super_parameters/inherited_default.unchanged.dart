// Omitting `id` passes null today. As `{super.id}` it would take the super
// constructor's default, 7, instead.
class Base {
  Base({this.id = 7});

  final int? id;
}

class Derived extends Base {
  Derived({int? id}) : super(id: id);
}
