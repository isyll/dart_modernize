// Negative: `T` is inferred FROM the argument, so the parameter contributes no
// concrete context type. `.red` would have no type to resolve against.
enum Color { red, green, blue }

void runWith<T>(T value) {}

void main() {
  runWith(Color.red);
}
