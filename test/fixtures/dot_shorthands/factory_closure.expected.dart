typedef Factory<T> = T Function();

class Registry {
  void bind<T>(Factory<T> create, {void Function(T)? dispose}) {}
}

class Session {
  Session({required this.id});

  final int id;

  void close() {}
}

void configure(Registry r) {
  r.bind<Session>(() => .new(id: 1), dispose: (s) => s.close());
}
