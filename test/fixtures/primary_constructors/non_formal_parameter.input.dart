class Timeout {
  final Duration duration;

  Timeout(int seconds) : duration = Duration(seconds: seconds);
}

class Scaled {
  final int _value;
  final String label;

  const Scaled(int raw, this.label) : _value = raw * 2;

  int get value => _value;
}
