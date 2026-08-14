enum Shape { circle, square }

void demo() {
  final items = <({Shape kind, String label})>[
    (kind: .circle, label: 'C'),
    (kind: .square, label: 'S'),
  ];
  print(items);
}
