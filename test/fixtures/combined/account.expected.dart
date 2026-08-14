import 'dart:collection';
import 'dart:math';

class Account {
  Account({required this.owner}) : id = _nextId++;

  Account.named(String owner) : this(owner: owner);

  static int _nextId = 0;

  final String owner;

  final int id;

  Level _level = .basic;

  Level get level => _level;

  Level classify(int score) => switch (score) {
    0 => .basic,
    _ => .premium,
  };

  String describe(String prefix) => '$prefix: $owner';

  Queue<String> history(String first) => Queue<String>()
    ..add(first)
    ..add(owner);

  List<int> merge(List<int> base, List<int>? extra) => [...base, ...?extra];

  void promote() => _level = .premium;

  static Account guest() => .new(owner: 'guest');

  static int roll() => Random().nextInt(6);
}

enum Level { basic, premium }
