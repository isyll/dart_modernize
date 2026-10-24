// A positional parameter forwarded as a named argument cannot become a
// positional `super.` parameter.
class Animated {
  Animated({required this.parent});

  final double parent;
}

class SizeAnimation extends Animated {
  SizeAnimation(double parent) : super(parent: parent);
}
