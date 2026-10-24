class TripStop {
  const TripStop(this.town, this.at);

  final String town;
  final int at;
}

class Trip {
  const Trip(this.stops);

  final List<TripStop> stops;
}
