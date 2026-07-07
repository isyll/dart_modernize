// Negative: the initializer is a method call whose static type is not obvious
// from the expression, so dropping the annotation would trip
// specify_nonobvious_local_variable_types. The annotation must stay.
class Foo {}

Foo makeFoo() => Foo();

void main() {
  Foo f = makeFoo();
  print(f);
}
