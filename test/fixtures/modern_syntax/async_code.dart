/// Async/await, Futures, and an async generator.
Future<int> fetch(int id) async {
  await Future<void>.delayed(Duration.zero);
  return id * 2;
}

Future<List<int>> fetchAll(List<int> ids) async {
  final results = <int>[];
  for (final id in ids) {
    results.add(await fetch(id));
  }
  return results;
}

Stream<int> countTo(int n) async* {
  for (var i = 1; i <= n; i++) {
    yield i;
  }
}
