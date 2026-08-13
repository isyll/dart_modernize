class Book extends Item with Describable {
  const Book(super.sku, this.cost);

  final double cost;

  @override
  String get label => 'book';

  @override
  double price() => cost;
}

class Bundle extends Item {
  Bundle(super.sku, this.items);

  final List<Item> items;

  @override
  double price() {
    var total = 0.0;
    for (final i in items) {
      total = total + i.price();
    }
    return total;
  }
}

mixin Describable {
  String get label;

  String describe() => 'item: $label';
}

sealed class Item {
  const Item(this.sku);

  final String sku;

  double price();
}
