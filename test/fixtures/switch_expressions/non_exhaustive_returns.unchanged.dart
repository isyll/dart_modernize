// Negative: there is no default and the int cases are not exhaustive. As a
// statement, unmatched values fall through to `return null`; a switch expression
// would have to be exhaustive, so converting the switch alone changes behaviour.
String? label(int code) {
  switch (code) {
    case 0:
      return 'zero';
    case 1:
      return 'one';
  }
  return null;
}
