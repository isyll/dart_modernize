// A named parameter forwarded as a positional argument cannot become a named
// `super.` parameter: the super constructor takes it positionally.
class ValueHolder {
  ValueHolder(this.value);

  final bool value;
}

class Controller extends ValueHolder {
  Controller({required bool canPop}) : super(canPop);
}
