enum Mode { fast, slow }

class Engine {
  Mode mode = .fast;

  void update(bool quick) {
    mode = quick ? .fast : .slow;
  }
}

Mode pick(bool quick) => quick ? .fast : .slow;
