enum Color { red, green, blue }

String label(Color c) {
  switch (c) {
    case .red:
      return 'r';
    case .green:
      return 'g';
    case .blue:
      return 'b';
  }
}
