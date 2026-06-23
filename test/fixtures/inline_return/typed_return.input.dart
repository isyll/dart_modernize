class Foo {}

Foo makeFoo() => Foo();

Foo result() {
  final Foo x = makeFoo();
  return x;
}
