Set<String> tags(String? primary) {
  final value = primary;
  return {'all', if (value != null) value};
}
