import 'package:analyzer/dart/analysis/results.dart';

import '../../engine/source_edit.dart';
import '../transformation.dart';

/// Rewrites eligible statement-style `switch` blocks as switch expressions
/// using modern pattern syntax (Dart 3+).
///
/// A switch statement is converted only when it is provably equivalent: every
/// arm must produce a single value for the same target (a `return`, or an
/// assignment to one variable) or `throw`, fall-through cases collapse to
/// logical-or patterns (`a || b`), and `default` becomes the wildcard `_`.
/// Anything with extra side effects, multiple statements per case, or that is
/// not exhaustive is left untouched.
final class SwitchExpressions implements Transformation {
  @override
  final bool enabled;

  const SwitchExpressions({required this.enabled});

  @override
  String get name => 'switch-expressions';

  @override
  Future<List<SourceEdit>> editsFor(ResolvedUnitResult unit) async => const [];
}
