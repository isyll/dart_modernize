List<String> compose(
  List<String> base,
  List<String>? prefix,
  List<String>? suffix,
) {
  return [...base, ...?prefix, 'separator', ...?suffix];
}
