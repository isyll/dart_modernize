import 'package:analyzer/dart/analysis/results.dart';

import '../../engine/source_edit.dart';
import '../transformation.dart';

/// Replaces null-guarded collection elements with the `?element` syntax.
///
/// Before: `[1, if (a != null) a]`
/// After:  `[1, ?a]`
final class NullAwareElements implements Transformation {
  @override
  final bool enabled;

  const NullAwareElements({required this.enabled});

  @override
  String get name => 'null-aware-elements';

  @override
  Future<List<SourceEdit>> editsFor(ResolvedUnitResult unit) async => const [];
}
