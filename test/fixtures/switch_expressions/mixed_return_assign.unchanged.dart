// Negative: some branches return while others assign a variable, so there is no
// single uniform target a switch expression could produce.
int score(int code) {
  var bonus = 0;
  switch (code) {
    case 0:
      return 100;
    case 1:
      bonus = 10;
      break;
    default:
      bonus = 0;
  }
  return bonus;
}
