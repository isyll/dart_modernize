List<String> build(
  String header,
  String body,
  bool showBody,
  List<String> sections,
) {
  final items = <String>[];
  items.add(header);
  if (showBody) items.add(body);
  for (final s in sections) items.add(s);
  return items;
}
