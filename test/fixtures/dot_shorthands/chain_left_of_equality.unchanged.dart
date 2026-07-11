// Negative: a dot shorthand is only valid on the right of `==`. The left
// operand has no context type, and a chain head inherits none there either, so
// the qualified head stays.
enum Color { red, green, blue }

bool isFirstRed(Color c) => Color.values.first == c;
