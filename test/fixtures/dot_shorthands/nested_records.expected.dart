enum E { a, b }

class Tag {
  const Tag(this.id);
  final int id;
}

void demo() {
  final rows = <((E, Tag), String)>[
    ((.a, .new(1)), 'first'),
    ((.b, .new(2)), 'second'),
  ];
  print(rows);
}
