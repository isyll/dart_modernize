import 'package:analyzer/dart/analysis/results.dart';

import '../../engine/source_edit.dart';
import '../transformation.dart';

/// Organizes directives via the in-process import organizer engine.
///
/// Runs in the finalize phase, not through [editsFor]; [editsFor] is a no-op.
final class OrganizeImports implements FinalizeTransformation {
  @override
  final bool enabled;

  const OrganizeImports({required this.enabled});

  @override
  String get name => 'organize-imports';

  @override
  Future<List<SourceEdit>> editsFor(ResolvedUnitResult unit) async => const [];
}
