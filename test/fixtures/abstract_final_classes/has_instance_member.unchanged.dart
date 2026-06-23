// Negative: the class has an instance method; it cannot be made abstract final.
class Formatter {
  static const String prefix = 'fmt';

  String format(String s) => '$prefix: $s';
}
