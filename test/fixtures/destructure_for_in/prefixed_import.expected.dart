import 'stops_model.dart' as model;

void report(List<model.TripStop> stops) {
  for (final model.TripStop(:town) in stops) {
    print(town);
  }
}
