// Support library imported with a prefix by the import_prefix_* cases. Not
// asserted on.
enum PermissionStatus { granted, limited, denied }

class Timeout {
  const Timeout(this.seconds);

  const Timeout.instant() : seconds = 0;

  final int seconds;

  static Timeout of(int seconds) => Timeout(seconds);
}
