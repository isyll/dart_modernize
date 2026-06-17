// Negative: the value is produced by a method call, which may have side effects
// and is evaluated twice in the if/value form. A null-aware element evaluates
// once, so collapsing is not behaviour-preserving here.
int? next() => 1;

List<int> build() {
  return [if (next() != null) next()!];
}
