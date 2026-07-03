sealed class Node {
  int get depth;

  const Node();
}

class Leaf extends Node {
  final int value;

  @override
  int get depth => 1;

  const Leaf(this.value);
}

class Branch extends Node {
  @override
  int get depth => 1 + child.depth;

  final Node child;

  const Branch(this.child);
}
