/// Complex inference: nested generics, null-aware ops, and closures.
Map<String, List<int>> grouped(List<int> values) {
  final result = <String, List<int>>{};
  for (final v in values) {
    final key = v.isEven ? 'even' : 'odd';
    (result[key] ??= []).add(v);
  }
  return result;
}

List<int> doubled(Iterable<int> xs) => xs.map((x) => x * 2).toList();

int Function(int) adder(int by) =>
    (x) => x + by;
