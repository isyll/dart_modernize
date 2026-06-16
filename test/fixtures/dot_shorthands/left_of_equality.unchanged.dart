// Negative: a dot shorthand is only allowed on the right-hand side of `==`/`!=`.
// The left operand has no context type, so this must stay fully qualified.
enum Status { active, inactive }

bool isActive(Status s) {
  return Status.active == s;
}
