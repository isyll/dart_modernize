// Negative: the cases do not cover every value and there is no default, so
// unmatched inputs leave the variable at its initialized value. A switch
// expression would have to be exhaustive, changing behaviour.
int weight(int code) {
  var w = -1;
  switch (code) {
    case 0:
      w = 1;
      break;
    case 1:
      w = 2;
      break;
  }
  return w;
}
