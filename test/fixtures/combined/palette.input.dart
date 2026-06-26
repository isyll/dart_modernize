class Palette {
  static const int max = 255;

  Palette._();

  static int lookup(String key) {
    var v = _cache[key];
    return v ?? 0;
  }

  static final Map<String, int> _cache = {};
}
