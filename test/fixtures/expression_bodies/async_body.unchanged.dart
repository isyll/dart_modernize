// Negative: an `async` body is left as a block even though it is a single
// return. A generator (`sync*`/`async*`) cannot be an arrow body at all, and
// async sugar is kept for clarity, so the pass stays its hand on any body with
// a leading keyword.
import 'dart:async';

Future<int> answer() async {
  return 42;
}
