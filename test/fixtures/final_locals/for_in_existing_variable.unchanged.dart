// `for (last in xs)` assigns the existing variable on every iteration.
int lastOf(List<int> xs) {
  var last = 0;
  for (last in xs) {}
  return last;
}
