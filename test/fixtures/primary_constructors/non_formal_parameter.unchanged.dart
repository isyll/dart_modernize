// Negative: `seconds` is a plain parameter feeding a computed field, not a
// `this.` initializing formal, so the class cannot collapse to a header.
class Timeout {
  final Duration duration;

  Timeout(int seconds) : duration = Duration(seconds: seconds);
}
