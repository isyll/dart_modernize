enum Mode { fast, slow }

Mode choose(bool quick) {
  Mode result = .fast;
  if (!quick) {
    result = .slow;
  }
  return result;
}
