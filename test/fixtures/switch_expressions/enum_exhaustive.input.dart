enum Direction { north, south, east, west }

String describe(Direction d) {
  switch (d) {
    case Direction.north:
      return 'up';
    case Direction.south:
      return 'down';
    case Direction.east:
      return 'right';
    case Direction.west:
      return 'left';
  }
}
