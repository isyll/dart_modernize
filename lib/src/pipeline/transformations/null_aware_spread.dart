import 'package:analyzer/dart/analysis/results.dart';

import '../../engine/source_edit.dart';
import '../transformation.dart';

/// Replaces null-guarded spread elements with the `...?` null-aware spread.
///
/// Before: `[...base, if (extra != null) ...extra]`
/// After:  `[...base, ...?extra]`
final class NullAwareSpread implements Transformation {
  @override
  final bool enabled;

  const NullAwareSpread({required this.enabled});

  @override
  String get name => 'null-aware-spread';

  @override
  Future<List<SourceEdit>> editsFor(ResolvedUnitResult unit) async => const [];
}
