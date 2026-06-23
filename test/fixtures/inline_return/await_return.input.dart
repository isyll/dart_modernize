Future<int> fetch() async => 42;

Future<int> result() async {
  final x = await fetch();
  return x;
}
