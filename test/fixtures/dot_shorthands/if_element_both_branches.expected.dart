class Foo {
  const Foo();
  const Foo.named();
}

List<Foo> build(bool condition) {
  return [if (condition) .new() else .named()];
}
