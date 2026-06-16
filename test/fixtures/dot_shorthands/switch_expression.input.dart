enum Color { red, green, blue }

Color fromCode(int code) => switch (code) {
  0 => Color.red,
  1 => Color.green,
  _ => Color.blue,
};
