// Negative: idiomatic, lint-clean code. `dart fix` has nothing to apply here.
int sum(List<int> values) {
  var total = 0;
  for (final value in values) {
    total += value;
  }
  return total;
}
