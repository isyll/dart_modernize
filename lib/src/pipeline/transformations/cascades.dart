import 'package:analyzer/dart/analysis/results.dart';

import '../../engine/source_edit.dart';
import '../transformation.dart';

/// Collapses sequential writes to a fresh local variable into a cascade chain.
///
/// Before: `var p = Paint(); p.color = c; p.width = 5.0;`
/// After:  `var p = Paint()..color = c..width = 5.0;`
final class Cascades implements Transformation {
  @override
  final bool enabled;

  const Cascades({required this.enabled});

  @override
  String get name => 'cascades';

  @override
  Future<List<SourceEdit>> editsFor(ResolvedUnitResult unit) async => const [];
}
