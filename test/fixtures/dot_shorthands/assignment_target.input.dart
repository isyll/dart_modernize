enum Mode { fast, slow }

Mode choose(bool quick) {
  Mode result = Mode.fast;
  if (!quick) {
    result = Mode.slow;
  }
  return result;
}
