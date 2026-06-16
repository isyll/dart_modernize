// Negative: the field is `_count` but the parameter is `value`. Folding into
// `this._count` derives the public name `count`, renaming the parameter and
// breaking every caller that passes `value:`.
class Counter {
  final int _count;

  Counter({required int value}) : _count = value;

  int get count => _count;
}
