class Key {
  const Key();
}

class Widget {
  final Key? key;

  const Widget({this.key});
}

class MyWidget extends Widget {
  const MyWidget({super.key});
}
