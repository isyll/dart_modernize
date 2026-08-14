// Negative: promoting would drop the annotation along with the field
// declaration, so the class is left alone. The annotation comes from the core
// library on purpose: a helper class declared here would itself be promotable.
class Config {
  @pragma('vm:entry-point')
  final int retries;

  Config(this.retries);
}
