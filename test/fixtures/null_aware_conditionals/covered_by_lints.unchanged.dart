// Negative: prefer_if_null_operators and prefer_null_aware_operators already
// fix both of these, so fix-all handles them and this pass stays out.
class Box {
  String get name => 'n';
}

String plain(String? value, String fallback) =>
    value == null ? fallback : value;

String? property(Box? box) => box == null ? null : box.name;
