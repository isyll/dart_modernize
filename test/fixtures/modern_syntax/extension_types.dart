/// An extension type wrapping a primitive with zero runtime cost.
extension type Meters(double value) {
  Meters operator +(Meters other) => Meters(value + other.value);

  double get inFeet => value * 3.28084;
}

double totalFeet(List<Meters> distances) {
  var sum = Meters(0);
  for (final d in distances) {
    sum = sum + d;
  }
  return sum.inFeet;
}
