import 'dart:convert';

String encode(Token t) => jsonEncode(t.value);

Token parse(int code) => switch (code) {
  0 => .new('zero'),
  _ => .new('other'),
};

class Token {
  Token(this.value);

  final String value;
}
