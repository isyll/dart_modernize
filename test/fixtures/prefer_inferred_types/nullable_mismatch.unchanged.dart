// Negative: the literal 0 has static type int (NullabilitySuffix.none) but
// the declared type is int? (NullabilitySuffix.question). The nullability
// differs, so the annotation must stay.
void main() {
  final int? x = 0;
  print(x);
}
