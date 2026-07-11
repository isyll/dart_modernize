// Negative: the class is instantiated through a dot-shorthand `.new()`, which
// counts as a use just like `Config()`. Marking it `abstract final` would turn
// that `.new()` into an instantiation of an abstract class.
class Config {
  static const String defaultName = 'app';
}

Config getConfig() => .new();
