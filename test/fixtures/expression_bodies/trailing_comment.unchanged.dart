// Negative: a trailing comment on the return statement would be lost in an `=>`
// rewrite, so the block body must stay.
int magic(int x) {
  return x * 42; // 42 is the answer.
}
