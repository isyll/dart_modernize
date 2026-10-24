class Box {
  Box? next;
  int size = 0;

  void grow(int by) => size += by;
}

void cases(Box? box, Box? other, bool flag) {
  // The argument reads `box`, which is not promoted inside `?.`.
  if (box != null) box.grow(box.size);
  // An else branch, or a different receiver.
  if (box != null) {
    box.grow(1);
  } else {
    print('none');
  }
  if (other != null) box?.grow(1);
  if (box != null && flag) box.grow(2);
  // A mutable field could change between the check and the call.
  final holder = Box();
  if (holder.next != null) holder.next!.grow(3);
  // Two statements.
  if (box != null) {
    box.grow(4);
    print('grown');
  }
}
