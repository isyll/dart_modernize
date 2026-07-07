enum Color { red, blue }

Iterable<Color> syncColors() sync* {
  yield Color.red;
  yield Color.blue;
}

Stream<Color> asyncColors() async* {
  yield Color.red;
}
