class Box {
  String get name => 'n';
}

String pick(Box? first, Box? second) =>
    first != null ? first.name : (second != null ? second.name : 'none');
