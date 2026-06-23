// Negative: one variable in the multi-var declaration is reassigned, so the
// whole declaration is left unchanged even though the other variable qualifies.
void multi() {
  var a = 1, b = 2;
  b = 3;
  print('$a $b');
}
