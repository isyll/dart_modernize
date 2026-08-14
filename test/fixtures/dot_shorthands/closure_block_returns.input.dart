enum WidgetState { disabled, selected }

typedef WidgetPropertyResolver<T> = T Function(Set<WidgetState> states);

class IconThemeData {
  IconThemeData({this.color});

  final int? color;
}

class WidgetStateProperty<T> {
  static WidgetStateProperty<T> resolveWith<T>(
    WidgetPropertyResolver<T> callback,
  ) => WidgetStateProperty<T>();
}

WidgetStateProperty<IconThemeData> iconTheme(int scheme) {
  return WidgetStateProperty.resolveWith<IconThemeData>((states) {
    if (states.contains(WidgetState.disabled)) {
      return IconThemeData(color: scheme);
    }
    if (states.contains(WidgetState.selected)) {
      return IconThemeData(color: scheme + 1);
    }
    return IconThemeData(color: scheme + 2);
  });
}
