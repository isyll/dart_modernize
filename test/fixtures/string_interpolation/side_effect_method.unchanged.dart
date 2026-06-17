// Negative: `next()` mutates state on each call, so the concatenated operand has
// a side effect. The guard requires side-effect-free pieces, so the chain is
// left alone.
class Counter {
  int _n = 0;

  String next() => '${_n++}';
}

String build(Counter c) {
  return 'id-' + c.next() + '-end';
}
