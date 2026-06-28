// Negative: only a plain `=` assignment yields a context type. A `??=` (or a
// compound `+=`) is left alone, so its right-hand side keeps the type prefix.
enum Mode { fast, slow }

Mode pick(Mode? current) {
  current ??= Mode.fast;
  return current;
}
