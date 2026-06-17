// Negative: a bare `return;` produces no value, so there is no expression for an
// `=>` body to carry.
void stop() {
  return;
}
