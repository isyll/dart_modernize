final sl = ServiceLocator();

void configureDependencies(AppConfig config, {CrashReporter? crashReporter}) {
  sl
    ..registerSingleton<AppConfig>(config)
    ..registerSingleton<CrashReporter>(crashReporter ?? .new())
    ..registerLazySingleton<ThemeCubit>(
      () => .new(config: sl()),
      dispose: (cubit) => cubit.close(),
    )
    ..registerLazySingleton<AuthApi>(
      () => config.baseUrl.isEmpty
          ? const FakeAuthApi()
          : HttpAuthApi(config: sl()),
    );
}

typedef FactoryFunc<T> = T Function();

class AppConfig {
  const new({required this.baseUrl});

  final String baseUrl;
}

abstract class AuthApi;

class CrashReporter;

class FakeAuthApi implements AuthApi {
  const new();
}

class HttpAuthApi implements AuthApi {
  new({required this.config});

  final AppConfig config;
}

class ServiceLocator {
  T call<T>() => throw UnimplementedError();

  void registerLazySingleton<T extends Object>(
    FactoryFunc<T> create, {
    void Function(T)? dispose,
  }) {}

  void registerSingleton<T extends Object>(T instance) {}
}

class ThemeCubit {
  new({required this.config});

  final AppConfig config;

  void close() {}
}
