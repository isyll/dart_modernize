class Foo {
  const Foo(int x);
}

List<Foo> build(List<int> values) {
  return <Foo>[for (final v in values) Foo(v)];
}
