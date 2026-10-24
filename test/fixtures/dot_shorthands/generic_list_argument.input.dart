enum Speed { bullet, blitz }

class IList<T> {
  IList(this.items);

  final List<T> items;
}

final speeds = IList([Speed.bullet, Speed.blitz]);
