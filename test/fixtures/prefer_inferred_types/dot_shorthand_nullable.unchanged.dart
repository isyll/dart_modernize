// Negative: the initializer's type (Foo) differs from the declared nullable type
// (Foo?), so dropping the annotation would change the declared type. The
// shorthand keeps its annotation.
class Foo {
  Foo();
}

void main() {
  final Foo? maybe = .new();
  print(maybe);
}
