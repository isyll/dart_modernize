enum Level { basic, premium }

Level classify(int score) {
  final result = switch (score) {
    0 => Level.basic,
    _ => Level.premium,
  };
  return result;
}

Future<List<int>> merge(List<int> base, List<int>? extra) async {
  final all = [...base, ...?extra];
  return all;
}
