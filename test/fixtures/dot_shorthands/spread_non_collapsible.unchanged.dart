// Negative: spread elements (...) are not expressions; the spread itself has no
// context type from which a dot-shorthand could be resolved.
class Foo {
  const Foo();
}

List<Foo> combine(List<Foo> a, List<Foo> b) {
  return [...a, ...b];
}
