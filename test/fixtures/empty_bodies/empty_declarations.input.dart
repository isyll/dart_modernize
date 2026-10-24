sealed class AuthState {}

final class AuthInitial extends AuthState {}

final class AuthLoading extends AuthState {}

class NetworkException implements Exception {}

mixin Loggable {}

extension type Id(int value) {}

extension StringX on String {}

mixin class Tracked {}
