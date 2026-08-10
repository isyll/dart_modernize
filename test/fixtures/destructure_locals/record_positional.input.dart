(int, String) computePair() => (1, 'one');

String describe() {
  final result = computePair();
  final a = result.$1;
  final b = result.$2;
  return '$a$b';
}
