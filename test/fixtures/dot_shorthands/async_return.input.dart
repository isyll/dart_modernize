class Session {}

Future<Session> open() async {
  return Session();
}

Future<Session> openFast() async => Session();
