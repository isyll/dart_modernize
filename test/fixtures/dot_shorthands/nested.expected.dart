enum Align { start, center, end }

class Box {
  final Align align;

  const Box.aligned(this.align);
}

List<Box> build() {
  return [.aligned(.start), .aligned(.center)];
}
