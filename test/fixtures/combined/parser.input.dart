import 'dart:convert';

class Token {
  final String value;

  Token(this.value);
}

Token parse(int code) {
  switch (code) {
    case 0:
      return Token('zero');
    default:
      return Token('other');
  }
}

String encode(Token t) => jsonEncode(t.value);
