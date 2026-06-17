// Negative: the switch performs side effects and yields no value, so it is not
// expressible as a value-producing switch expression.
void route(int code, List<String> sink) {
  switch (code) {
    case 0:
      sink.add('a');
      break;
    default:
      sink.add('b');
  }
}
