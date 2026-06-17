// Negative: `current` is a getter that may return a different value on each
// read. The if/value form reads it twice (test, then value); `?source.current`
// would read it once. Rewriting could change behaviour, so it must stay.
class Source {
  int _n = 0;

  int? get current => _n++ == 0 ? 1 : null;
}

List<int> drain(Source source) {
  return [if (source.current != null) source.current!];
}
