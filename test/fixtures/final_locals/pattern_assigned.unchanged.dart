// A pattern assignment writes to existing variables, so they must stay `var`.
(int, int) snap(int a, int b) => (b, a);

int swap() {
  var first = 1;
  var last = 2;
  (first, last) = snap(first, last);
  return first + last;
}

int fromList(List<int> xs) {
  var head = 0;
  [head, ...] = xs;
  return head;
}
