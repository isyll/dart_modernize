import 'stops_model.dart' as model;

void report(List<model.TripStop> stops) {
  for (final stop in stops) {
    print(stop.town);
  }
}
