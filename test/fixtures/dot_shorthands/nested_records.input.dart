enum E { a, b }

class Tag {
  const Tag(this.id);
  final int id;
}

void demo() {
  final rows = [
    ((E.a, Tag(1)), 'first'),
    ((E.b, Tag(2)), 'second'),
  ];
  print(rows);
}
