// Negative: a record field typed dynamic is not precise, so no field of the
// record shortens (not even the enum one) and nothing is hoisted.
enum E { a, b }

final List<(E, dynamic)> rows = [(E.a, 1)];
