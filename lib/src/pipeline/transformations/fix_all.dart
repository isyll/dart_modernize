import 'package:analyzer/dart/analysis/results.dart';

import '../../engine/source_edit.dart';
import '../transformation.dart';

/// Delegates to `dart fix --apply` over the whole project directory.
///
/// Runs in the finalize phase, not through [editsFor]; [editsFor] is a no-op.
final class FixAll implements FinalizeTransformation {
  const FixAll({required this.enabled});

  @override
  final bool enabled;

  @override
  String get name => 'fix-all';

  @override
  Future<List<SourceEdit>> editsFor(ResolvedUnitResult unit) async => const [];
}
