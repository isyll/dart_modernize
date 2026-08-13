import 'dart:collection';
import 'dart:convert';
import 'dart:math';

String demo() {
  final q = Queue<int>()..add(Random().nextInt(10));
  return jsonEncode(q.toList());
}
