class Theme {
  Theme._();

  static Theme get light => Theme._();
}

Theme current() {
  Theme t = Theme.light;
  return t;
}
