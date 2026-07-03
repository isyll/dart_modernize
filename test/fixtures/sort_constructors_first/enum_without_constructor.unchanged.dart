// Negative: an enum with no declared constructor; the constants and members
// are already in a valid order, so nothing moves.
enum Direction {
  north,
  south;

  Direction get opposite => this == north ? south : north;
}
