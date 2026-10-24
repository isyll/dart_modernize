enum Level { basic, premium }

Level classify(int score) {
  return switch (score) {
    0 => Level.basic,
    _ => Level.premium,
  };
}

Future<List<int>> merge(List<int> base, List<int>? extra) async {
  return [...base, ...?extra];
}
