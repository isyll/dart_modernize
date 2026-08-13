abstract final class Palette {
  static const max = 255;

  static final _cache = <String, int>{};

  static int lookup(String key) {
    final v = _cache[key];
    return v ?? 0;
  }
}
