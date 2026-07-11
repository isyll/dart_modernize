enum ThemeMode { system, light, dark }

ThemeMode restore(String? saved) {
  return ThemeMode.values.asNameMap()[saved] ?? ThemeMode.system;
}

ThemeMode chained(ThemeMode? preferred, String? saved) {
  return preferred ?? ThemeMode.values.asNameMap()[saved] ?? ThemeMode.system;
}
