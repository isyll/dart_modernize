// Negative: `parse` is static on `int`, but the context type here is `num`.
// A `.parse` shorthand would resolve against `num`, which has no such member.
num parsed = int.parse('42');
