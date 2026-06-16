import 'dart:math';
import 'dart:collection';
import 'dart:convert';

String demo() {
  final q = Queue<int>()..add(Random().nextInt(10));
  return jsonEncode(q.toList());
}
