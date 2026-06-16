class Box<T> {
  final T _value;

  Box({required T value}) : _value = value;

  T get value => _value;
}
