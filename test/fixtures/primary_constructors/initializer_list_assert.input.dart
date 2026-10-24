class Age {
  final int years;

  Age(this.years) : assert(years >= 0);
}

class Range {
  final int min;
  final int max;

  const Range(this.min, this.max) : assert(min <= max), assert(max < 100);

  int get span => max - min;
}
