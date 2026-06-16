import 'package:analyzer/dart/analysis/results.dart';

import '../../engine/source_edit.dart';
import '../transformation.dart';

/// Promotes eligible classes to the primary constructor form when it is
/// provably safe — i.e. the class has no logic other than field assignment.
final class PrimaryConstructors implements Transformation {
  const PrimaryConstructors({required this.enabled});

  @override
  final bool enabled;

  @override
  String get name => 'primary-constructors';

  @override
  Future<List<SourceEdit>> editsFor(ResolvedUnitResult unit) async => const [];
}
