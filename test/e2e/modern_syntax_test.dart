import '../support/e2e.dart';

/// Runs every stable pass over a spread of already-modern Dart 3.12 files
/// (records, patterns, sealed classes, mixins, extension types, async, …) and
/// asserts the tool never breaks them: it runs cleanly, the result still
/// analyzes, and a second run changes nothing.
void main() => defineRobustnessSuite(
  label: 'modern syntax robustness',
  dir: 'modern_syntax',
  args: allStablePasses,
);
