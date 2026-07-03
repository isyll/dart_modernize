class First {
  int x = 0;

  void aMethodWithAQuiteLongBodyToShiftManyBytes() {
    x = x + 1;
    x = x + 2;
    x = x + 3;
  }

  First(this.x);
}

class Second {
  final String name;

  final int count;

  String describe() => '$name x $count';

  Second(this.name, this.count);
}

class Third {
  void onlyMethod() {}

  Third.named() : this._internal();

  Third._internal();
}
