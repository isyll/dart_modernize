enum Planet {
  earth(5.97),
  mars(0.64);

  const Planet(this.mass);

  final double mass;

  double get relative => mass / 5.97;
}
