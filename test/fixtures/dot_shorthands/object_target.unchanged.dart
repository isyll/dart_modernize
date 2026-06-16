// Negative: the context type is `Object`, which does not declare `red`. A
// `.red` shorthand would resolve against `Object` and fail to compile.
enum Color { red, green, blue }

Object favorite = Color.red;
