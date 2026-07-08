import 'package:analyzer/dart/analysis/results.dart';

import '../../engine/source_edit.dart';
import '../transformation.dart';

/// Reorders members via the in-process member sorter engine.
///
/// Runs in the finalize phase, not through [editsFor]; [editsFor] is a no-op.
final class SortMembers implements FinalizeTransformation {
  const SortMembers({required this.enabled});

  @override
  final bool enabled;

  @override
  String get name => 'sort-members';

  @override
  Future<List<SourceEdit>> editsFor(ResolvedUnitResult unit) async => const [];
}
