enum Color { red, green, blue }

String label(Color c) {
  switch (c) {
    case Color.red:
      return 'r';
    case Color.green:
      return 'g';
    case Color.blue:
      return 'b';
  }
}
