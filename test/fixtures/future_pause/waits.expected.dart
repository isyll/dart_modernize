Future<void> settle() async {
  await Future.pause(const Duration(milliseconds: 300));
  await Future.pause();
  await Future.pause(const Duration(seconds: 1));
}

Future<void> later() => Future.pause(const Duration(seconds: 2));

void fireAndForget() {
  Future.pause(const Duration(seconds: 1));
}
