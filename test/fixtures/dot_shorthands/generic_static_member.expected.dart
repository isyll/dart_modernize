class Box<T> {
  const Box(this.value);

  final T value;

  static Box<X> of<X>(X value) => .new(value);

  static Box<int> get zero => const .new(0);
}

Box<String>? make() => .of('hi');

Box<int>? origin() => .zero;
