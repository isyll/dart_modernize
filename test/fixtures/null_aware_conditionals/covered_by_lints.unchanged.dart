// Negative: both of these are what prefer_if_null_operators and
// prefer_null_aware_operators already fix, so the fix-all pass owns them and
// this pass deliberately stays out. A bare reference is `x ?? d`; a property
// read against a null alternative is `x?.name`.
class Box {
  String get name => 'n';
}

String plain(String? value, String fallback) =>
    value == null ? fallback : value;

String? property(Box? box) => box == null ? null : box.name;
