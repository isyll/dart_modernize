// Negative: the `case 1` branch breaks out of the switch instead of returning,
// so execution continues at the statement after the switch. The arms are not
// uniformly value-producing, so this is not a switch expression.
String classify(int code) {
  switch (code) {
    case 0:
      return 'zero';
    case 1:
      break;
    default:
      return 'many';
  }
  return 'fallback';
}
