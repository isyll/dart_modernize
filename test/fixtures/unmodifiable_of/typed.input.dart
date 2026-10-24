final List<int> ids = List.unmodifiable(<int>[1, 2]);

List<String> names(Iterable<String> all) => List.unmodifiable(all);

Map<String, int> freeze(Map<String, int> m) => Map.unmodifiable(m);
