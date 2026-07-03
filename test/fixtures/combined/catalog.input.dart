mixin Describable {
  String get label;

  String describe() => 'item: ' + label;
}

sealed class Item {
  final String sku;

  double price();

  const Item(this.sku);
}

class Book extends Item with Describable {
  final double cost;

  @override
  String get label => 'book';

  @override
  double price() => cost;

  const Book(String sku, this.cost) : super(sku);
}

class Bundle extends Item {
  @override
  double price() {
    var total = 0.0;
    for (final i in items) {
      total = total + i.price();
    }
    return total;
  }

  final List<Item> items;

  Bundle(String sku, this.items) : super(sku);
}
