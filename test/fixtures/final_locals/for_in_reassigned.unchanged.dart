// Negative: the loop variable is reassigned in the body, so it cannot be final.
void use(int value) {}

void loop(List<int> xs) {
  for (var x in xs) {
    x = x * 2;
    use(x);
  }
}
