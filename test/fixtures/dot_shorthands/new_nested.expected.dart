class Inner {
  const Inner();
}

class Outer {
  final Inner inner;

  const Outer(this.inner);
}

Outer build() {
  return .new(.new());
}
