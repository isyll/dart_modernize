// Negative: `var` infers its type FROM the initializer. Collapsing to `.red`
// would leave the compiler with no context type to infer, so it must stay.
enum Color { red, green, blue }

var favorite = Color.red;
