void report(Map<String, int> scores) {
  for (final entry in scores.entries) {
    print('${entry.key} = ${entry.value}');
  }
}
