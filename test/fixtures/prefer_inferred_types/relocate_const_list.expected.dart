enum Category { massage, spa }

class Filters {
  final available = const <Category>[Category.massage];
  final ids = const <int>{1, 2};
  final weights = const <String, int>{'a': 1};
}

void f() {
  final names = const <String>[];
  print(names);
}
