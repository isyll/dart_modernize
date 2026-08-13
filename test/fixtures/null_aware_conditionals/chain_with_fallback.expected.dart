class Box {
  String get name => 'n';
  List<int> get items => const [];
  int size() => 0;
}

String named(Box? box, String fallback) => box?.name ?? fallback;

String namedReversed(Box? box, String fallback) => box?.name ?? fallback;

int depth(Box? box) => box?.items.length ?? 0;

int called(Box? box) => box?.size() ?? -1;

int indexed(List<int>? xs) => xs?[0] ?? -1;
