// Negative: a dot-shorthand initializer resolves only against the declared
// type, so the annotation must stay. (This is the already-modernized form; the
// pass must not break it on a re-run.)
enum Mode { fast, slow }

class Box {
  const Box(this.w);

  final int w;
}

class Config {
  static const Box unit = .new(1);
  static const Mode mode = .fast;
}
