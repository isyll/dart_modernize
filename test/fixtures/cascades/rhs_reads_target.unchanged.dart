// Negative: a write's right-hand side references the target variable itself. In
// a declaration cascade the receiver is not yet bound to `n`, so `..parent = n`
// would read an unbound variable; the ordering is not equivalent.
class Node {
  Node? parent;
  int value = 0;
}

Node build() {
  var n = Node();
  n.value = 1;
  n.parent = n;
  return n;
}
