enum Category { massage, spa }

class Filters {
  final List<Category> available = const [Category.massage];
  final Set<int> ids = const {1, 2};
  final Map<String, int> weights = const {'a': 1};
}

void f() {
  final List<String> names = const [];
  print(names);
}
