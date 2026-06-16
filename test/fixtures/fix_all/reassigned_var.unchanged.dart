// Negative: `total` is reassigned in the loop, so prefer_final_locals does not
// apply. `dart fix` must leave it as `var`.
int sum(List<int> xs) {
  var total = 0;
  for (final x in xs) {
    total += x;
  }
  return total;
}
