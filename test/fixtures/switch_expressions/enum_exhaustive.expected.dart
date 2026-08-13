enum Direction { north, south, east, west }

String describe(Direction d) {
  return switch (d) {
    Direction.north => 'up',
    Direction.south => 'down',
    Direction.east => 'right',
    Direction.west => 'left',
  };
}
