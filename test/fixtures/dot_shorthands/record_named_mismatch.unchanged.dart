// Negative: the named field's context type (Animal) differs from the written
// type (Dog); shortening would resolve `.new()` against Animal, so it stays.
class Animal {}

class Dog extends Animal {}

final List<({Animal pet})> pets = [(pet: Dog())];
