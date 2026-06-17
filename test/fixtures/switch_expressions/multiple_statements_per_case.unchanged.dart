// Negative: a case runs more than one statement (a side effect *and* the
// assignment), which a single switch-expression arm cannot express.
int classify(int code, List<String> log) {
  int result;
  switch (code) {
    case 0:
      log.add('zero');
      result = 10;
      break;
    default:
      result = 20;
  }
  return result;
}
