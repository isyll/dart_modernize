// Negative: `var` infers its type from the initializer, so there is no context
// type for `.new` to resolve against; the constructor call must stay explicit.
class Service {
  Service();
}

void main() {
  var s = Service();
  print(s);
}
