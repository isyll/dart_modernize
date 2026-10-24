final List<int> ids = List.unmodifiableOf(<int>[1, 2]);

List<String> names(Iterable<String> all) => List.unmodifiableOf(all);

Map<String, int> freeze(Map<String, int> m) => Map.unmodifiableOf(m);
