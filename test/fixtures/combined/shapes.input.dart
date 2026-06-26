import 'dart:math';
import 'dart:collection';
import 'dart:convert';

enum Shape { circle, square, triangle }

class Renderer {
  String describe(Shape s) {
    String label;
    switch (s) {
      case Shape.circle:
        label = 'round';
        break;
      case Shape.square:
      case Shape.triangle:
        label = 'angular';
        break;
    }
    return label;
  }

  final String _name;

  Renderer({required String name}) : _name = name;

  String get name => _name;
}

Queue<int> seedQueue(int seed) {
  var q = Queue<int>();
  q.add(seed);
  q.add(seed + 1);
  return q;
}

Shape defaultShape() {
  return Shape.circle;
}

List<int> gather(List<int> base, List<int>? extra) {
  final all = [...base, if (extra != null) ...extra];
  return all;
}

String greet(String who) {
  final msg = 'Hello, ' + who + '!';
  return msg;
}

double randomUnit() => Random().nextDouble();
