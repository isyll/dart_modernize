Map<String, int> merge(Map<String, int>? overrides) {
  final extra = overrides;
  return {'base': 0, if (extra != null) ...extra};
}
