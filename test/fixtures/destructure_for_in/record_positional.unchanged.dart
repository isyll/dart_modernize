// Negative: a positional record field has no name to bind, and this pass never
// invents an identifier.
void render(List<(int, String)> pairs) {
  for (final pair in pairs) {
    print('${pair.$1}: ${pair.$2}');
  }
}
