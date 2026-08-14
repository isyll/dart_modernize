enum Color { red, green, blue }

Color fromCode(int code) => switch (code) {
  0 => .red,
  1 => .green,
  _ => .blue,
};
