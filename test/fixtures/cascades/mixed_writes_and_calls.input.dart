class Config {
  String name = '';
  int timeout = 0;
  final List<String> flags = [];

  void enable(String flag) => flags.add(flag);
}

Config defaults() {
  final config = Config();
  config.name = 'app';
  config.enable('verbose');
  config.timeout = 30;
  config.enable('color');
  return config;
}
