/// Thrown when modernization cannot proceed safely.
final class ModernizeException implements Exception {
  const ModernizeException(this.message);

  final String message;

  @override
  String toString() => 'ModernizeException: $message';
}
