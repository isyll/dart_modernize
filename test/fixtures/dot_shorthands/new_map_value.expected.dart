class Foo {
  const Foo();
}

Map<String, Foo> registry() {
  return {'a': .new()};
}
