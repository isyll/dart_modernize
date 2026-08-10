class Box {
  String get name => 'n';
  List<int> get items => const [];
  int size() => 0;
}

String named(Box? box, String fallback) =>
    box != null ? box.name : fallback;

String namedReversed(Box? box, String fallback) =>
    box == null ? fallback : box.name;

int depth(Box? box) => box != null ? box.items.length : 0;

int called(Box? box) => box != null ? box.size() : -1;

int indexed(List<int>? xs) => xs != null ? xs[0] : -1;
