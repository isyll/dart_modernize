// Negative: the annotation would be dropped along with the field declaration.
class Marker {
  const Marker();
}

class Config {
  @Marker()
  final int retries;

  Config(this.retries);
}
