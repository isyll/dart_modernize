// Negative: the context type is `dynamic`, so there is no static type to infer
// the member from. Collapsing to `.red` would not compile — leave it alone.
enum Color { red, green, blue }

dynamic chosen = Color.red;
