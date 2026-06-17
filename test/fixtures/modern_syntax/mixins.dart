/// A mixin applied to a class.
mixin Greeter {
  String get greeting => 'hello';

  String greet(String name) => '$greeting, $name';
}

class Robot with Greeter {
  final String id;

  Robot(this.id);

  String announce() => greet(id);
}
