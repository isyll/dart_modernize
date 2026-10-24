class Age(final int years) {
  this : assert(years >= 0);
}

class const Range(final int min, final int max) {
  this : assert(min <= max), assert(max < 100);

  int get span => max - min;
}
