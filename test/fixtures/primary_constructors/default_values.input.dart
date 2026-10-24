class Config {
  final String host;
  final int port;
  final Duration? timeout;

  Config({
    required this.host,
    this.port = 8080,
    this.timeout = const Duration(seconds: 5),
  });
}

class Pair {
  final int a;
  final int b;

  Pair(this.a, [this.b = 2]);
}

class Window {
  final int width;
  final int? height;
  final bool visible;

  Window(this.width, [this.height]) : visible = true;
}

class CartState {
  final List<String> items;
  final int total;

  const CartState(this.total, {this.items = const []});
}
