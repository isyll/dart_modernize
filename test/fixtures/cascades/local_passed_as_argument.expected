class Config {
  String host = '';
  int port = 0;
  void validate() {}
}

void register(Config c) {}

void setup() {
  final c = Config()
    ..host = 'localhost'
    ..port = 8080
    ..validate();
  register(c);
}
