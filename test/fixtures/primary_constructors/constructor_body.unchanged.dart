// Negative: the constructor runs logic beyond field initialization, so it is
// not a pure primary-constructor candidate.
class Logger {
  final String name;

  Logger(this.name) {
    print('created $name');
  }
}
