// Negative: the positional field context (Animal) is a supertype of the written
// type (Dog); shortening would change the resolved element, so it stays.
class Animal {}

class Dog extends Animal {}

final List<(Animal, int)> pairs = [(Dog(), 1)];
