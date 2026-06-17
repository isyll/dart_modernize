List<int> build(List<int>? extra) {
  return [0, if (extra != null) ...extra];
}
