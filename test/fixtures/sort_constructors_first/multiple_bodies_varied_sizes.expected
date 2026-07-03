class First {
  First(this.x);

  int x = 0;

  void aMethodWithAQuiteLongBodyToShiftManyBytes() {
    x = x + 1;
    x = x + 2;
    x = x + 3;
  }
}

class Second {
  Second(this.name, this.count);

  final String name;

  final int count;

  String describe() => '$name x $count';
}

class Third {
  Third.named() : this._internal();

  Third._internal();

  void onlyMethod() {}
}
