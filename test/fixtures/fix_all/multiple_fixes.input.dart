class Animal {
  String speak() => 'generic';
}

class Cat extends Animal {
  String speak() {
    var sound = 'meow';
    return sound;
  }
}
