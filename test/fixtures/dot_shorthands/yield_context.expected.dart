enum Color { red, blue }

Iterable<Color> syncColors() sync* {
  yield .red;
  yield .blue;
}

Stream<Color> asyncColors() async* {
  yield .red;
}
