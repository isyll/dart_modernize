enum Shape { circle, square }

void demo() {
  final items = [
    (kind: Shape.circle, label: 'C'),
    (kind: Shape.square, label: 'S'),
  ];
  print(items);
}
