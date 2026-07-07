enum StockReadingType { opening, midday, closing }

class IconData {
  const IconData(this.code);
  final int code;
}

class Icons {
  static const IconData sunny = .new(1);
  static const IconData twilight = .new(2);
  static const IconData night = .new(3);
}

List<(StockReadingType, String, IconData)> buildOptions() {
  final options = <(StockReadingType, String, IconData)>[
    (.opening, 'Opening', Icons.sunny),
    (.midday, 'Midday', Icons.twilight),
    (.closing, 'Closing', Icons.night),
  ];
  return options;
}
