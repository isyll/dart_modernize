class Builder {
  final List<String> _parts = [];

  void add(String s) => _parts.add(s);
  void clear() => _parts.clear();
}

Builder build() {
  var b = Builder()
    ..add('a')
    ..add('b')
    ..clear();
  return b;
}
