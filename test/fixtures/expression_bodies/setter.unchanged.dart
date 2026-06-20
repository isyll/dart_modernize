// Negative: a setter's single-statement body could syntactically become an `=>`
// body, but setters are intentionally left untouched, so this stays a block.
class C {
  int _x = 0;

  set value(int v) {
    _x = v;
  }
}
