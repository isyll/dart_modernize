// Negative: the loop variable is compound-assigned, which is still a write.
void use(int value) {}

void loop(List<int> xs) {
  for (var x in xs) {
    x += 1;
    use(x);
  }
}
