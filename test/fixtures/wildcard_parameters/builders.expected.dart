typedef Builder = String Function(int index, String label, Object error);

String separator(int _, String _) => '-';

final builders = <Builder>[(_, _, _) => 'broken', (index, _, _) => '$index'];

void guarded(void Function() action) {
  try {
    action();
  } catch (_, _) {
    print('failed');
  }
}
