int score(String grade) {
  final points = switch (grade) {
    'A' => 4,
    'B' => 3,
    _ => 0,
  };
  return points;
}
