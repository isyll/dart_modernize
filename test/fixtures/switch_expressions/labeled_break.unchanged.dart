// Negative: a labeled `break` transfers control to a label outside the switch
// (the enclosing loop). Such break tricks have no value-producing switch
// expression equivalent.
int run(int code) {
  var result = 0;
  loop:
  while (true) {
    switch (code) {
      case 0:
        result = 1;
        break loop;
      default:
        result = 2;
        break loop;
    }
  }
  return result;
}
