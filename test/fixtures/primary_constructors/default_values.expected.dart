class Config({
  required final String host,
  final int port = 8080,
  final Duration? timeout = const Duration(seconds: 5),
});

class Pair(final int a, [final int b = 2]);

class Window(final int width, [final int? height]) {
  final bool visible = true;
}

class const CartState(final int total, {final List<String> items = const []});
