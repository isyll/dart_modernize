enum LocationAccuracy { low, medium, high }

Stream<int> watch({
  LocationAccuracy accuracy = LocationAccuracy.high,
  int distanceFilterMeters = 25,
}) async* {
  yield distanceFilterMeters;
}

LocationAccuracy pick([LocationAccuracy accuracy = LocationAccuracy.low]) {
  return accuracy;
}

class Marker {
  Marker({this.accuracy = LocationAccuracy.medium});

  final LocationAccuracy accuracy;
}
