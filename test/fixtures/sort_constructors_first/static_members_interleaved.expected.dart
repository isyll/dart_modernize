class Counter {
  Counter(this.start);

  static int instances = 0;

  final int start;

  static Counter create() => Counter(0);

  int get current => start;

  static const int max = 100;
}
