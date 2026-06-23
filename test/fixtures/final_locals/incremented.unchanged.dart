// Negative: the variable is incremented after declaration.
int counter() {
  var x = 0;
  x++;
  return x;
}
