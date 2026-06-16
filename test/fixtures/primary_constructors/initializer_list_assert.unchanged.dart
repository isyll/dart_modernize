// Negative: the constructor has an initializer-list entry (an assert) that a
// mechanical primary-constructor promotion would silently drop.
class Age {
  final int years;

  Age(this.years) : assert(years >= 0);
}
