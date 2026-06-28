enum Mode { fast, slow }

class Engine {
  Mode mode = Mode.fast;

  void update(bool quick) {
    mode = quick ? Mode.fast : Mode.slow;
  }
}

Mode pick(bool quick) => quick ? Mode.fast : Mode.slow;
