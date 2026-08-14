enum LocationAccuracy { low, medium, high }

Stream<int> watch({
  LocationAccuracy accuracy = .high,
  int distanceFilterMeters = 25,
}) async* {
  yield distanceFilterMeters;
}

LocationAccuracy pick([LocationAccuracy accuracy = .low]) {
  return accuracy;
}

class Marker {
  Marker({this.accuracy = .medium});

  final LocationAccuracy accuracy;
}
