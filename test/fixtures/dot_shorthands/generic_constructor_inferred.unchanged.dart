// Negative: when a generic constructor has no explicit type arguments, its
// type is inferred from the arguments. Collapsing an argument to a shorthand
// would erase the only thing the type could be inferred from, so the arguments
// are left as-is.
class Token {
  Token(this.id);

  final int id;
}

class Pair<T> {
  Pair(this.first, this.second);

  final T first;
  final T second;
}

Pair<Token> pairOf() {
  final p = Pair(Token(1), Token(2));
  return p;
}
