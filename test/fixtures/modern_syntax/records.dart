/// Records: named and positional fields, returning records, and destructuring.
({int min, int max}) bounds(List<int> values) {
  var lo = values.first;
  var hi = values.first;
  for (final v in values) {
    if (v < lo) lo = v;
    if (v > hi) hi = v;
  }
  return (min: lo, max: hi);
}

int span(List<int> values) {
  final (min: lo, max: hi) = bounds(values);
  return hi - lo;
}

(String, int) labelled() => ('count', 3);
