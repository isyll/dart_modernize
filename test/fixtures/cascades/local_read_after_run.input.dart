class Widget {
  String label = '';
  int size = 0;
  void show() {}
}

String describe(Widget w) => w.label;

void configure() {
  var w = Widget();
  w.label = 'hello';
  w.size = 10;
  w.show();
  print(describe(w));
}
