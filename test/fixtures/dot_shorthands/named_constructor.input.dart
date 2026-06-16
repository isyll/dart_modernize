class Temperature {
  final double celsius;

  const Temperature.celsius(this.celsius);
}

Temperature freezing() {
  Temperature t = Temperature.celsius(0);
  return t;
}
