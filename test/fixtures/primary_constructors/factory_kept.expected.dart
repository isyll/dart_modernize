enum Kind { a, b }

class Item(final Kind kind, final bool isPrivate) {
  factory Item.named(Kind kind, String name) =>
      Item(kind, name.startsWith('_'));
}
