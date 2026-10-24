class Counter {
  new(this.count);
  new zero() : count = 0;
  factory parse(String s) => Counter(int.parse(s));

  final int count;
}
