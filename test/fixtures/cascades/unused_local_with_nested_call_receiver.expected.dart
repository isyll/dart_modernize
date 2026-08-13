int compute(int x) => x * 2;

class Builder {
  final int value;
  Builder(int x, {required int extra}) : value = x + extra;
  void setA(int v) {}
  void setB(String s) {}
}

void build() {
  Builder(compute(21), extra: compute(1))
    ..setA(42)
    ..setB('done');
}
