class Animal {
  String speak() => 'generic';
}

class Cat extends Animal {
  @override
  String speak() {
    final sound = 'meow';
    return sound;
  }
}
