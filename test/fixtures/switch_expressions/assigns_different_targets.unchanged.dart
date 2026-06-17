// Negative: branches assign different variables, so there is no single target
// for a switch expression to produce.
(int, int) split(int code) {
  var a = 0;
  var b = 0;
  switch (code) {
    case 0:
      a = 1;
      break;
    default:
      b = 1;
  }
  return (a, b);
}
