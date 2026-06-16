class Box<T> {
  final T _value;

  Box({required this._value});

  T get value => _value;
}
