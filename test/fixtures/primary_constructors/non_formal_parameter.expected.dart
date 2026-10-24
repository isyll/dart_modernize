class Timeout(int seconds) {
  final Duration duration = Duration(seconds: seconds);
}

class const Scaled(int raw, final String label) {
  final int _value = raw * 2;

  int get value => _value;
}
