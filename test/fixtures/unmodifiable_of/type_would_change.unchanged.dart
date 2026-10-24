// Without a context `List.unmodifiable([1, 2])` is a `List<dynamic>`, where
// `List.unmodifiableOf` would infer `List<int>`; and in a `List<num>` context
// the `Iterable<int>` argument would decide the type instead.
final loose = List.unmodifiable([1, 2]);

List<num> widen(List<int> xs) => List.unmodifiable(xs);
