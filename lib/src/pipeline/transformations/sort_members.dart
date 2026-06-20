import 'package:analyzer/dart/analysis/results.dart';

import '../../engine/source_edit.dart';
import '../transformation.dart';

/// Reorders class members via the analysis server's sortMembers request.
///
/// Runs in the finalize phase, not through [editsFor]; [editsFor] is a no-op.
final class SortMembers implements FinalizeTransformation {
  @override
  final bool enabled;

  const SortMembers({required this.enabled});

  @override
  String get name => 'sort-members';

  @override
  Future<List<SourceEdit>> editsFor(ResolvedUnitResult unit) async => const [];
}
