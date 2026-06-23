// Negative: the variable is reassigned after declaration.
int counter() {
  var x = 0;
  x = 10;
  return x;
}
