List<String> compose(
  List<String> base,
  List<String>? prefix,
  List<String>? suffix,
) {
  return [
    ...base,
    if (prefix != null) ...prefix,
    'separator',
    if (suffix != null) ...suffix,
  ];
}
