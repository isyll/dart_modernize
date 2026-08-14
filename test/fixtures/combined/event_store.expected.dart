import 'dart:collection';
import 'dart:math';

class EventStore {
  EventStore({required this.logger});
  static final _events = <String>[];

  final Logger logger;

  int get total => _events.length;

  Queue<String> buildLog(String first) => Queue<String>()
    ..add(first)
    ..add(logger.format('start'));

  List<int> collect(List<int> base, List<int>? extra) => [...base, ...?extra];

  static void record(String event) => _events.add(event);
}

enum Level { debug, info, warn }

class Logger {
  Logger({required this._prefix});

  final String _prefix;

  Level _level = .debug;

  Level get level => _level;

  Level classify(int code) => switch (code) {
    0 => .debug,
    1 => .info,
    _ => .warn,
  };

  void escalate() => _level = .warn;

  String format(String message) => '$_prefix: $message';
}

abstract final class MathUtils {
  static int roll() => Random().nextInt(6);
}
