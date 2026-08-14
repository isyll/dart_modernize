class Theme {
  Theme._();

  static Theme get light => ._();
}

Theme current() {
  Theme t = .light;
  return t;
}
