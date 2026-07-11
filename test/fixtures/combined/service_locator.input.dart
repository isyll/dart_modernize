typedef FactoryFunc<T> = T Function();

class ServiceLocator {
  T call<T>() => throw UnimplementedError();

  void registerSingleton<T extends Object>(T instance) {}

  void registerLazySingleton<T extends Object>(
    FactoryFunc<T> create, {
    void Function(T)? dispose,
  }) {}
}

final sl = ServiceLocator();

class AppConfig {
  const AppConfig({required this.baseUrl});

  final String baseUrl;
}

class CrashReporter {}

class ThemeCubit {
  ThemeCubit({required this.config});

  final AppConfig config;

  void close() {}
}

abstract class AuthApi {}

class FakeAuthApi implements AuthApi {
  const FakeAuthApi();
}

class HttpAuthApi implements AuthApi {
  HttpAuthApi({required this.config});

  final AppConfig config;
}

void configureDependencies(AppConfig config, {CrashReporter? crashReporter}) {
  sl
    ..registerSingleton<AppConfig>(config)
    ..registerSingleton<CrashReporter>(crashReporter ?? CrashReporter())
    ..registerLazySingleton<ThemeCubit>(
      () => ThemeCubit(config: sl()),
      dispose: (cubit) => cubit.close(),
    )
    ..registerLazySingleton<AuthApi>(
      () => config.baseUrl.isEmpty
          ? const FakeAuthApi()
          : HttpAuthApi(config: sl()),
    );
}
