enum ThemeMode { system, light, dark }

ThemeMode restore(String? saved) {
  return .values.asNameMap()[saved] ?? .system;
}

ThemeMode chained(ThemeMode? preferred, String? saved) {
  return preferred ?? .values.asNameMap()[saved] ?? .system;
}
