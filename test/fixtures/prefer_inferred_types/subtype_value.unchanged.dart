// Negative: the initializer's type (Dog) is a subtype of the declared type
// (Animal), not the same type. The annotation narrows the static view and must
// be kept.
class Animal {}

class Dog extends Animal {}

void main() {
  final Animal a = Dog();
  print(a);
}
