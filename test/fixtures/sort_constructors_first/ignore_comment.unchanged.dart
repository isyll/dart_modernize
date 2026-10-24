// The author keeps this constructor after the fields on purpose and says so;
// moving it would leave the ignore comment pointing at nothing.
class Breakpoint {
  final int columns;
  final double gutter;

  // ignore: sort_constructors_first
  const Breakpoint({required this.columns, required this.gutter});
}
