// Negative: the local is both returned and passed as an argument; the
// sole-immediate-return check fails because log(conn) follows the cascade run.
// With only one cascade-eligible operation the cascade fold also does not apply,
// so the file is left byte-for-byte unchanged.
class Connection {
  String host = '';
  int port = 0;
  void open() {}
}

void log(Connection c) {}

Connection connect() {
  var conn = Connection();
  conn.host = 'example.com';
  log(conn);
  return conn;
}
