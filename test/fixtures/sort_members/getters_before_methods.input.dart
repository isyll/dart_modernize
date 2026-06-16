class Temp {
  double toFahrenheit() => _celsius * 9 / 5 + 32;

  double get celsius => _celsius;

  final double _celsius;

  Temp(this._celsius);
}
