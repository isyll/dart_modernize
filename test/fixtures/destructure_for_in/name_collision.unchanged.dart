// Negative: binding `:value` would introduce a `value` that clashes with the
// local already declared in the enclosing function.
void report(Map<String, int> scores) {
  final value = 0;
  for (final entry in scores.entries) {
    print(entry.value + value);
  }
}
