/// Thrown by a `--check` run when at least one file would change.
///
/// It is a control-flow signal, not an error: the summary line is already
/// printed by the reporter, so the CLI catches this and exits non-zero without
/// printing anything more (mirroring `dart format --set-exit-if-changed`).
final class const CheckModifiedException() implements Exception {
  @override
  String toString() => 'CheckModifiedException';
}

/// Thrown when modernization cannot proceed safely.
final class const ModernizeException(final String message)
    implements Exception {
  @override
  String toString() => 'ModernizeException: $message';
}
