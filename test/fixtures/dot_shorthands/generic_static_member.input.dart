class Box<T> {
  const Box(this.value);

  final T value;

  static Box<X> of<X>(X value) => Box<X>(value);

  static Box<int> get zero => const Box(0);
}

Box<String>? make() => Box.of('hi');

Box<int>? origin() => Box.zero;
