// Negative: `area` is a computed getter, not a final field. Destructuring would
// evaluate it once per iteration instead of once per use, which is observable
// for a getter that runs code.
class Box {
  const Box(this.width);
  final int width;
  int get area => width * width;
}

void render(List<Box> boxes) {
  for (final box in boxes) {
    print(box.area);
  }
}
