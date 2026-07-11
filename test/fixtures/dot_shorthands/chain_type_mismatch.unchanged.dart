// Negative: the chain's context type is `num`, but its head references `int`.
// A `.parse` shorthand would resolve against `num`, which has no `parse`, so a
// chain head stays qualified whenever its referenced type differs from the
// whole chain's context type.
num scaled(String raw) => int.parse(raw).toDouble();
