// Negative: the `case 1` branch performs no assignment, so the variable keeps
// its initialized value. A switch expression must yield a value in every arm,
// so there is no behaviour-preserving rewrite.
int normalize(int code) {
  var result = -1;
  switch (code) {
    case 0:
      result = 100;
      break;
    case 1:
      break;
    default:
      result = 0;
  }
  return result;
}
