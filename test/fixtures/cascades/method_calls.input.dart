class Builder {
  final List<String> _parts = [];

  void add(String s) => _parts.add(s);
  void clear() => _parts.clear();
}

Builder build() {
  var b = Builder();
  b.add('a');
  b.add('b');
  b.clear();
  return b;
}
