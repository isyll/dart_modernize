class Box {
  final int x;
  final int y;

  Box(this.x, this.y);
}

void main() {
  const a = 1;
  const b = 2;
  const c = 3;
  final boxes = <Box>[.new(a, b), .new(a, c)];
  print(boxes);
}
