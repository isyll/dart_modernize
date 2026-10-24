Future<int> answer() => Future.delayed(const Duration(seconds: 1), () => 42);

Future<int?> typed() => Future<int?>.delayed(const Duration(seconds: 1));

Future<void> chained() async {
  await Future.delayed(const Duration(seconds: 1)).then((_) => print('done'));
  final wait = Future.delayed(const Duration(seconds: 1));
  await wait;
}
