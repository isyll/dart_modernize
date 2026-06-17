class Box {
  final int _value;

  Box(this._value);

  int get value {
    return _value;
  }

  int doubled() {
    return _value * 2;
  }
}
