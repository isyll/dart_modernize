import 'package:analyzer/dart/analysis/results.dart';

import '../../engine/source_edit.dart';
import '../transformation.dart';

/// Moves constructor declarations before all other members in every class,
/// mixin, enum, extension, and extension-type body.
///
/// Runs in the finalize phase, after [sort_members] has settled the canonical
/// order (fields then constructors then methods). This pass then lifts
/// constructors before the fields so the final order satisfies the
/// `sort_constructors_first` lint: constructors, then all other members.
///
/// [editsFor] is a no-op; the real work happens in the pipeline's
/// [_finalize] step via [sortConstructorsFirstEdits].
final class SortConstructorsFirst implements FinalizeTransformation {
  @override
  final bool enabled;

  const SortConstructorsFirst({required this.enabled});

  @override
  String get name => 'sort-constructors-first';

  @override
  Future<List<SourceEdit>> editsFor(ResolvedUnitResult unit) async => const [];
}
