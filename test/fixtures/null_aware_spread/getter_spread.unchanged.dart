// Negative: `items` is a getter that may return a different list (or null) on
// each read. The if/spread form reads it twice; `...?source.items` reads once,
// so collapsing could change behaviour and must not apply.
class Source {
  int _calls = 0;

  List<int>? get items => _calls++ == 0 ? const [1, 2] : null;
}

List<int> build(Source source) {
  return [if (source.items != null) ...source.items!];
}
