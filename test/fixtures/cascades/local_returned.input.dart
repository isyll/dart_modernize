class Connection {
  String host = '';
  int port = 0;
  void open() {}
}

Connection connect() {
  var conn = Connection();
  conn.host = 'example.com';
  conn.port = 443;
  conn.open();
  return conn;
}
