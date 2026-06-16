import 'package:analyzer/dart/analysis/results.dart';

import '../engine/source_edit.dart';

/// A single modernization pass over a resolved Dart compilation unit.
///
/// Implement this interface to add a new transformation rule.
/// Each implementation must be stateless — [editsFor] may be called
/// concurrently for different units.
abstract interface class Transformation {
  /// Short identifier shown in progress output, e.g. `'dot-shorthands'`.
  String get name;

  /// When false the transformation is skipped for every file.
  bool get enabled;

  /// Returns the edits to apply to [unit].
  ///
  /// Must not modify [unit]. Returns an empty list when no edits apply.
  Future<List<SourceEdit>> editsFor(ResolvedUnitResult unit);
}
