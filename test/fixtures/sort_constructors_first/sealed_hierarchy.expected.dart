sealed class Node {
  const Node();

  int get depth;
}

class Leaf extends Node {
  const Leaf(this.value);

  final int value;

  @override
  int get depth => 1;
}

class Branch extends Node {
  const Branch(this.child);

  @override
  int get depth => 1 + child.depth;

  final Node child;
}
