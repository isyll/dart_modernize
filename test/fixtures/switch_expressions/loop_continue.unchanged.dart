// Negative: the bare `continue` targets the enclosing `for` loop, not the
// switch. Folding the switch into an expression would discard that control-flow
// effect.
int sumNonNegative(List<int> values) {
  var total = 0;
  for (final v in values) {
    switch (v.sign) {
      case -1:
        continue;
      default:
        total += v;
    }
  }
  return total;
}
