class Record {
  final String name;

  Record(this.name);

  // Set to false once the record is archived.
  bool active = true;

  int get length => name.length;
}
