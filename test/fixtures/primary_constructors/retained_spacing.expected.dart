class Record(final String name) {
  // Set to false once the record is archived.
  bool active = true;

  int get length => name.length;
}
