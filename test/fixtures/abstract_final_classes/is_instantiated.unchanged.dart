// Negative: the class is instantiated within the project.
class Config {
  static const String defaultName = 'app';
}

Config getConfig() => Config();
