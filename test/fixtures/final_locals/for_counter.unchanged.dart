// Negative: the variable is compound-assigned inside a loop.
int sum(int n) {
  var total = 0;
  for (var i = 0; i < n; i++) {
    total += i;
  }
  return total;
}
