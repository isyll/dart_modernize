// TripStop is only inferred here, never imported, so `final TripStop(...)`
// would not compile.
import 'stops_api.dart';

void report() {
  for (final stop in loadTrip().stops) {
    print('${stop.town} ${stop.at}');
  }
}
