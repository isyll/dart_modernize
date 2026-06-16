// Negative: the constructor does not bind the parameter straight to the field —
// it transforms the value (`* 2`). A private named parameter (`this._scaled`)
// would change behaviour, so this must not be folded.
class Scaled {
  final int _scaled;

  Scaled({required int value}) : _scaled = value * 2;

  int get value => _scaled;
}
