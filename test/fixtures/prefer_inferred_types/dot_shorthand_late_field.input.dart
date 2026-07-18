class Channel {}

class AuthClient {
  AuthClient(Channel channel, {int? options});
}

class Clients {
  Clients(this._channel);

  final Channel _channel;

  late final AuthClient auth = .new(_channel, options: 1);
}
