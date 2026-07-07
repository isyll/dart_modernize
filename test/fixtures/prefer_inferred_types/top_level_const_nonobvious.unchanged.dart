// Negative: the initializer is a binary expression whose type is not obvious
// from the syntax. Dropping the annotation would trip
// specify_nonobvious_property_types, so the type stays.
const int total = 1 + 2;
