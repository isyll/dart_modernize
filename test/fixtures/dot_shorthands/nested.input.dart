enum Align { start, center, end }

class Box {
  final Align align;

  const Box.aligned(this.align);
}

List<Box> build() {
  return [Box.aligned(Align.start), Box.aligned(Align.center)];
}
