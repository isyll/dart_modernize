// The context of an `async` return value is `FutureOr<(bool, Product?)>`,
// which gives the fields of a record literal no context at all, so
// `.category(...)` would not resolve.
class Product {
  const Product.category(this.name);

  final String name;

  static Product parse(String s) {
    final product = Product.category(s);
    return product;
  }
}

Future<(bool, Product?)> exitPage(String name) async {
  return (true, Product.category(name));
}

Future<(bool, Product?)> parsePage(String name) async =>
    (false, Product.parse(name));

Future<({Product? site})> fetch(bool found) async {
  return (site: found ? Product.parse('x') : null);
}
