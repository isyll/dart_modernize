// Negative: explicit element type is dynamic; _sameType(dynamic, Foo) is false
// so no shorthand can be resolved.
class Foo {
  const Foo();
}

void main() {
  final items = <dynamic>[
    for (final i in [1, 2]) Foo(),
  ];
  print(items);
}
