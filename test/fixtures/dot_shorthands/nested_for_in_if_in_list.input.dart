class Foo {
  const Foo(int x);
}

List<Foo> build(bool condition, List<int> values) {
  return [
    if (condition)
      for (final v in values) Foo(v),
  ];
}
