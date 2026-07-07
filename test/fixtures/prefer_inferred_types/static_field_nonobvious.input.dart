class IconData {
  const IconData(this.code);
  final int code;
}

class Icons {
  static const IconData network = IconData(0xe1);
}

class AppIcons {
  static const IconData stationsFill = Icons.network;
}
