// `ISetConst<T>` and `IMap<K, V>` infer their type arguments from the
// literal, so the literal's elements have no context type.
enum Speed { bullet, blitz }

class Score {
  const Score.fromJson(this.value);

  final int value;
}

class ISetConst<T> {
  const ISetConst(this.set);

  final Set<T> set;
}

class IMap<K, V> {
  IMap(this.map);

  final Map<K, V> map;
}

const speeds = ISetConst({Speed.bullet, Speed.blitz});

int count(Map<String, int> raw) {
  final scores = IMap({
    for (final MapEntry(:key, :value) in raw.entries)
      key: Score.fromJson(value),
  });
  return scores.map.length;
}
