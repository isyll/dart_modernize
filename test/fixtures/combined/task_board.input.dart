import 'dart:math';
import 'dart:collection';

enum Priority { low, high }

class Task {
  String get name => _name;

  final String _name;
  final Priority priority;

  Task({required String name, required this.priority}) : _name = name;
}

int weightOf(int code) {
  int result;
  switch (code) {
    case 0:
      result = 1;
      break;
    default:
      result = 5;
  }
  return result;
}

Queue<Task> pending() {
  final q = Queue<Task>();
  q.add(Task(name: 'seed', priority: Priority.low));
  return q;
}

int roll() => Random().nextInt(6);
