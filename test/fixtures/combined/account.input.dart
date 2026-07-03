import 'dart:math';
import 'dart:collection';

class Account {
  static int _nextId = 0;

  final String owner;

  final int id;

  Level _level = Level.basic;

  void promote() {
    _level = Level.premium;
  }

  Level get level => _level;

  Account({required this.owner}) : id = _nextId++;

  static Account guest() {
    return Account(owner: 'guest');
  }

  Account.named(String owner) : this(owner: owner);

  String describe(String prefix) {
    final label = prefix + ': ' + owner;
    return label;
  }

  Level classify(int score) {
    Level result;
    switch (score) {
      case 0:
        result = Level.basic;
        break;
      default:
        result = Level.premium;
    }
    return result;
  }

  Queue<String> history(String first) {
    var q = Queue<String>();
    q.add(first);
    q.add(owner);
    return q;
  }

  List<int> merge(List<int> base, List<int>? extra) {
    final all = [...base, if (extra != null) ...extra];
    return all;
  }

  static int roll() => Random().nextInt(6);
}

enum Level { basic, premium }
