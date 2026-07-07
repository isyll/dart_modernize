enum StockReadingType { opening, midday, closing }

class IconData {
  const IconData(this.code);
  final int code;
}

class Icons {
  static const IconData sunny = IconData(1);
  static const IconData twilight = IconData(2);
  static const IconData night = IconData(3);
}

List<(StockReadingType, String, IconData)> buildOptions() {
  final options = [
    (StockReadingType.opening, 'Opening', Icons.sunny),
    (StockReadingType.midday, 'Midday', Icons.twilight),
    (StockReadingType.closing, 'Closing', Icons.night),
  ];
  return options;
}
