class Registry {
  void put<T>(T value) {}
}

class Config {
  const Config();
}

class Reporter {}

void configure(Registry r, Reporter? reporter) {
  r
    ..put<Config>(const .new())
    ..put<Reporter>(reporter ?? .new());
}
