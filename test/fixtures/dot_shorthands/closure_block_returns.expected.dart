enum WidgetState { disabled, selected }

typedef WidgetPropertyResolver<T> = T Function(Set<WidgetState> states);

class IconThemeData {
  IconThemeData({this.color});

  final int? color;
}

class WidgetStateProperty<T> {
  static WidgetStateProperty<T> resolveWith<T>(
    WidgetPropertyResolver<T> callback,
  ) => .new();
}

WidgetStateProperty<IconThemeData> iconTheme(int scheme) {
  return .resolveWith<IconThemeData>((states) {
    if (states.contains(WidgetState.disabled)) {
      return .new(color: scheme);
    }
    if (states.contains(WidgetState.selected)) {
      return .new(color: scheme + 1);
    }
    return .new(color: scheme + 2);
  });
}
