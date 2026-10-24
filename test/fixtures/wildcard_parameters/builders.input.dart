typedef Builder = String Function(int index, String label, Object error);

String separator(int _, String __) => '-';

final builders = <Builder>[
  (_, __, ___) => 'broken',
  (index, __, ___) => '$index',
];

void guarded(void Function() action) {
  try {
    action();
  } catch (_, __) {
    print('failed');
  }
}
