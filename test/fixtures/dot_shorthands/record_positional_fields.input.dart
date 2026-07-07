enum Shape { circle, square }

class Paint {
  const Paint(this.rgb);
  final int rgb;
}

void demo() {
  final items = [
    (Shape.circle, Paint(0xff0000)),
    (Shape.square, Paint(0x00ff00)),
  ];
  print(items);
}
