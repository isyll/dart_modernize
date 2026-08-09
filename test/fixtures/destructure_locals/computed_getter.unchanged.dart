// Negative: `area` is a computed getter, not a final field. Destructuring would
// move when it runs, which is observable for a getter that runs code.
class Box {
  const Box(this.width);
  final int width;
  int get area => width * width;
}

Box getBox() => const Box(3);

int compute() {
  final box = getBox();
  final area = box.area;
  return area;
}
