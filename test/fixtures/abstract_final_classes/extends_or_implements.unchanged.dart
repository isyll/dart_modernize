// Negative: a class that extends or implements another type is never sealed,
// even with only static members and no use in the project. Sealing it would
// stop it being created as that type (test mocks are the usual case).
class Logger {
  void log(String message) {}
}

class SilentLogger extends Logger {
  static const tag = 'silent';
}

abstract interface class Marker {}

class Tagged implements Marker {
  static const id = 1;
}
