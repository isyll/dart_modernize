enum Color { red, blue }

Color pick(Color? maybe) {
  return maybe ?? .red;
}

Color choose(Color? maybe) {
  final Color c = maybe ?? .blue;
  return c;
}
