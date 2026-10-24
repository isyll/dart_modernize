// In the declaration `fold` infers `Map<String, int>` from its seed. In the
// `return` of an async body its context is `FutureOr<Map<String, int>>`, and
// inference would pick that for the accumulator, which has no `[]=`.
Future<Map<String, int>> countWords(List<String> words) async {
  final counts = words.fold(<String, int>{}, (map, word) {
    map[word] = (map[word] ?? 0) + 1;
    return map;
  });
  return counts;
}
