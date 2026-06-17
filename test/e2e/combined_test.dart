import '../support/e2e.dart';

/// Production-like files that deliberately combine several transformations.
/// Each is modernized end-to-end and must match its golden, analyze clean, and
/// be idempotent — validating that the passes compose correctly.
void main() => defineCombinedGoldenSuite(
  label: 'combined transformations',
  dir: 'combined',
  args: allStablePasses,
);
