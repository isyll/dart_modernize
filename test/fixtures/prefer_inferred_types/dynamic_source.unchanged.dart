// Negative: the initializer returns dynamic, which is not an InterfaceType.
// The declared type (int) is more specific; removing the annotation would
// widen the type to dynamic.
dynamic dynamicValue() => 42;

void main() {
  final int x = dynamicValue();
  print(x);
}
