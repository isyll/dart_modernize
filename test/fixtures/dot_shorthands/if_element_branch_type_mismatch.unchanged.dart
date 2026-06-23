// Negative: Bar extends Foo so both branches are valid list elements, but
// _sameType(Foo, Bar) is false; the written type must match the context exactly.
class Foo {
  const Foo();
}

class Bar extends Foo {
  const Bar();
}

List<Foo> build(bool b) {
  return [if (b) Bar() else Bar()];
}
