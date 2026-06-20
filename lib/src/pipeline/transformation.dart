import 'package:analyzer/dart/analysis/results.dart';

import '../engine/source_edit.dart';

/// Marker for passes that run in the finalize phase, not through [editsFor].
///
/// Fix-all, organize-imports, and sort-members all delegate to external tools
/// (dart fix, the analysis server) rather than walking the AST. They implement
/// [Transformation] only to carry the [enabled] flag through the pipeline;
/// their [editsFor] always returns an empty list.
///
/// The pipeline detects [FinalizeTransformation] instances and routes them to
/// [ModernizePipeline._finalize] instead of the main AST loop.
abstract interface class FinalizeTransformation implements Transformation {}

/// A single modernization pass over a resolved Dart compilation unit.
///
/// Implement this interface to add a new transformation rule.
/// Each implementation must be stateless; [editsFor] may be called
/// concurrently for different units.
abstract interface class Transformation {
  /// When false the transformation is skipped for every file.
  bool get enabled;

  /// Short identifier shown in progress output, e.g. `'dot-shorthands'`.
  String get name;

  /// Returns the edits to apply to [unit].
  ///
  /// Must not modify [unit]. Returns an empty list when no edits apply.
  Future<List<SourceEdit>> editsFor(ResolvedUnitResult unit);
}
