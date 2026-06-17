// Negative: the condition is a value test, not a `!= null` check. A null-aware
// element only models the null guard, so this conditional must stay.
List<int> build(int a) {
  return [if (a > 0) a];
}
