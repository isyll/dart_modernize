// Untyped, `[1, 2]` is a `List<int>`; returned from a `List<num>` function it
// would become a `List<num>`.
List<num> numbers() {
  final values = [1, 2];
  return values;
}

double half() {
  final x = 1;
  return x / 2;
}
