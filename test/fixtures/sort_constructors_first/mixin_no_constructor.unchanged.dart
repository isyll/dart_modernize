// Negative: mixins cannot declare constructors, so no reorder can occur.
mixin Loggable {
  String get tag;

  void log(String msg) => print('[$tag] $msg');
}
