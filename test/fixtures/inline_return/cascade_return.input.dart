class Connection {
  String host = '';
  int port = 0;
  void open() {}
}

Connection connect() {
  var conn = Connection()
    ..host = 'example.com'
    ..port = 443
    ..open();
  return conn;
}
