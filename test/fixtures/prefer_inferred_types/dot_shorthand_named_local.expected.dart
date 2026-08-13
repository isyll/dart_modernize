class Temperature {
  Temperature.celsius(this.degrees);

  final int degrees;
}

void main() {
  final t = Temperature.celsius(0);
  print(t);
}
