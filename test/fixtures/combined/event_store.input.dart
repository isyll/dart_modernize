import 'dart:math';
import 'dart:collection';

enum Level { debug, info, warn }

class MathUtils {
  MathUtils._();

  static int roll() {
    return Random().nextInt(6);
  }
}

class Logger {
  final String _prefix;

  Logger({required String prefix}) : _prefix = prefix;

  Level _level = Level.debug;

  void escalate() {
    _level = Level.warn;
  }

  Level get level => _level;

  String format(String message) {
    final line = _prefix + ': ' + message;
    return line;
  }

  Level classify(int code) {
    Level result;
    switch (code) {
      case 0:
        result = Level.debug;
        break;
      case 1:
        result = Level.info;
        break;
      default:
        result = Level.warn;
    }
    return result;
  }
}

class EventStore {
  static final List<String> _events = [];
  final Logger logger;

  EventStore({required this.logger});

  static void record(String event) {
    _events.add(event);
  }

  int get total => _events.length;

  Queue<String> buildLog(String first) {
    var q = Queue<String>();
    q.add(first);
    q.add(logger.format('start'));
    return q;
  }

  List<int> collect(List<int> base, List<int>? extra) {
    final all = [...base, if (extra != null) ...extra];
    return all;
  }
}
