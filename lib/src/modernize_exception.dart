/// Thrown when modernization cannot proceed safely.
final class ModernizeException implements Exception {
  final String message;

  const ModernizeException(this.message);

  @override
  String toString() => 'ModernizeException: $message';
}
