class Config {
  String name = '';
  int timeout = 0;
}

Config? setup(bool enable) {
  if (enable) {
    var cfg = Config();
    cfg.name = 'enabled';
    cfg.timeout = 60;
    return cfg;
  }
  return null;
}
