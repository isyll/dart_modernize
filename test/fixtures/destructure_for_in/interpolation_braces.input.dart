void report(Map<String, int> scores) {
  for (final entry in scores.entries) {
    print('${entry.key}s scored ${entry.value}');
  }
}
