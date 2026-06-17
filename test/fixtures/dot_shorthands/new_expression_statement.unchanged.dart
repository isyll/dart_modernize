// Negative: a bare constructor call used as a statement has no surrounding
// context type, so `.new` cannot be inferred.
class Service {
  Service();
}

void main() {
  Service();
}
