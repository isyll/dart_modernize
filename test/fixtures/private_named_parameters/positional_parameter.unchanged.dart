// Negative: this pass targets *named* parameters only. A positional
// initializing formal is a separate, pre-existing idiom and is left untouched
// by the private-named-parameters pass.
class Wrapper {
  final int _value;

  Wrapper(int value) : _value = value;

  int get value => _value;
}
