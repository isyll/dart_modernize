/// Thrown by a `--check` run when at least one file would change.
///
/// It is a control-flow signal, not an error: the summary line is already
/// printed by the reporter, so the CLI catches this and exits non-zero without
/// printing anything more (mirroring `dart format --set-exit-if-changed`).
final class const CheckModifiedException() implements Exception {
  @override
  String toString() => 'CheckModifiedException';
}

/// Thrown after a run that applied its changes but had to revert some files
/// because they stopped compiling.
///
/// The summary and the reverted files are already printed; the CLI exits with
/// code 2 so a script can tell this apart from a run that failed (1) or
/// changed everything it meant to (0).
final class const PartialSuccessException() implements Exception {
  @override
  String toString() => 'PartialSuccessException';
}

/// Thrown when modernization cannot proceed safely.
final class const ModernizeException(final String message)
    implements Exception {
  @override
  String toString() => 'ModernizeException: $message';
}
