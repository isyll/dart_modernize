// Negative: even in a const context the declared type is `Object`, which does
// not declare `red`. A `.red` shorthand would resolve against `Object` and fail
// to compile, so the const enum value must stay fully qualified.
enum Color { red, green, blue }

const Object favorite = Color.red;
