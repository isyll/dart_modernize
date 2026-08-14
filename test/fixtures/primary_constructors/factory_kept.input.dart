enum Kind { a, b }

class Item {
  final Kind kind;
  final bool isPrivate;

  Item(this.kind, this.isPrivate);

  factory Item.named(Kind kind, String name) => Item(kind, name.startsWith('_'));
}
