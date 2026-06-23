class Config {
  String host = '';
  int port = 0;
  void validate() {}
}

void register(Config c) {}

void setup() {
  final c = Config();
  c.host = 'localhost';
  c.port = 8080;
  c.validate();
  register(c);
}
