class Widget {
  final String a;
  final String b;

  Widget({this.a = '', this.b = ''});
}

List<Widget> build(String a, String b) {
  return [Widget(a: a, b: b), Widget(a: 'genial')];
}
