// Negative: a static-member shorthand (an enum value or a static getter) would
// expand to a non-obvious property access, so dropping the annotation would trip
// specify_nonobvious_*. Only constructor shorthands are expanded; the annotation
// must stay here.
enum Mode { fast, slow }

class Config {
  static const Mode mode = .fast;
  final Duration span = .zero;
}
