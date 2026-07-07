enum Color { red, blue }

Color pick(Color? maybe) {
  return maybe ?? Color.red;
}

Color choose(Color? maybe) {
  final Color c = maybe ?? Color.blue;
  return c;
}
