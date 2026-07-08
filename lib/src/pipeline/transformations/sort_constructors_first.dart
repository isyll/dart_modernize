import 'package:analyzer/dart/analysis/results.dart';

import '../../engine/source_edit.dart';
import '../transformation.dart';

/// Moves constructor declarations before all other members in every class,
/// mixin, enum, extension, and extension-type body.
///
/// Runs in the finalize phase, after `sort-members`. Because `sort-members`
/// already emits constructors first, this pass is a no-op whenever it ran; it
/// still exists so users can satisfy the `sort_constructors_first` lint without
/// the full member reorder, and it never fights `sort-members`: its output is a
/// fixed point of both passes.
///
/// [editsFor] is a no-op; the real work happens in the pipeline's
/// [_finalize] step via [sortConstructorsFirstEdits].
final class SortConstructorsFirst implements FinalizeTransformation {
  const SortConstructorsFirst({required this.enabled});

  @override
  final bool enabled;

  @override
  String get name => 'sort-constructors-first';

  @override
  Future<List<SourceEdit>> editsFor(ResolvedUnitResult unit) async => const [];
}
