Future<void> settle() async {
  await Future.delayed(const Duration(milliseconds: 300));
  await Future.delayed(Duration.zero);
  await Future<void>.delayed(const Duration(seconds: 1));
}

Future<void> later() => Future.delayed(const Duration(seconds: 2));

void fireAndForget() {
  Future.delayed(const Duration(seconds: 1));
}
