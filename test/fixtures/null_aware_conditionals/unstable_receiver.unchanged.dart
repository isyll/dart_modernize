// Negative: the tested expression is a field, not a local or a parameter, so it
// is not a stable reference; reading it twice is not guaranteed to be
// side-effect free or to yield the same value.
class Box {
  String get name => 'n';
}

class Holder {
  Holder(this._box);
  final Box? _box;

  String describe(String fallback) => _box != null ? _box.name : fallback;
}
