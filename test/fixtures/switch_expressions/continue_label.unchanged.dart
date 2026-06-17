// Negative: `continue label` is an explicit fall-through that re-enters another
// case's body. A switch expression cannot model labeled fall-through.
String walk(int code) {
  String out = '';
  switch (code) {
    label:
    case 0:
      out = 'zero';
      break;
    case 1:
      out = 'one';
      continue label;
    default:
      out = 'other';
  }
  return out;
}
