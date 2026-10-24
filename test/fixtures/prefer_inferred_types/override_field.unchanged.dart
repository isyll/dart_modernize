// Without a type, a field that overrides an inherited member takes that
// member's type, not its initializer's: `objects` would become an
// `ObjectSetStats` and every caller expecting an `ObjectSet` would break.
class ObjectSetStats {}

class ObjectSet extends ObjectSetStats {}

abstract class ClassData {
  ObjectSetStats get objects;
}

class SingleClassData extends ClassData {
  @override
  final ObjectSet objects = ObjectSet();
}

abstract class Snapshot {
  List<ObjectSetStats> get items;
}

class FakeSnapshot implements Snapshot {
  // Overrides `items` without an `@override` annotation.
  final List<ObjectSet> items = <ObjectSet>[];
}
