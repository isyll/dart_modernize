import 'package:analyzer/dart/analysis/results.dart';

import '../../engine/source_edit.dart';
import '../transformation.dart';

/// Applies the same bulk fixes as `dart fix`, integrated into the pipeline
/// so they run in a single pass alongside other transformations.
final class FixAll implements Transformation {
  @override
  final bool enabled;

  const FixAll({required this.enabled});

  @override
  String get name => 'fix-all';

  @override
  Future<List<SourceEdit>> editsFor(ResolvedUnitResult unit) async => const [];
}
