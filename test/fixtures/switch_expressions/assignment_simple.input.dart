int score(String grade) {
  int points;
  switch (grade) {
    case 'A':
      points = 4;
      break;
    case 'B':
      points = 3;
      break;
    default:
      points = 0;
  }
  return points;
}
