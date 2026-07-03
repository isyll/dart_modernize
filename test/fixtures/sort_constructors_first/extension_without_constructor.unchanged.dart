// Negative: a plain extension cannot declare constructors, so the pass has
// nothing to move even though a getter precedes a method.
extension StringExtras on String {
  bool get isBlank => trim().isEmpty;

  String repeatTwice() => this + this;
}
