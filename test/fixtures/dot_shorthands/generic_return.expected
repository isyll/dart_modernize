sealed class Result<T> {
  const factory Result.success(T value) = Success<T>;
  const factory Result.failure(Object error) = Failure<T>;
}

class Success<T> implements Result<T> {
  const Success(this.value);

  final T value;
}

class Failure<T> implements Result<T> {
  const Failure(this.error);

  final Object error;
}

Result<T> ok<T>(T value) => .success(value);

Future<Result<T>> guarded<T>(Future<T> Function() action) async {
  try {
    return .success(await action());
  } catch (error) {
    return .failure(error);
  }
}
