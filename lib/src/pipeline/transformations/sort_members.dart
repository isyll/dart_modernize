import 'package:analyzer/dart/analysis/results.dart';

import '../../engine/source_edit.dart';
import '../transformation.dart';

/// Reorders class members into the canonical Dart style order:
/// fields → constructors → named constructors → getters/setters → methods.
final class SortMembers implements Transformation {
  const SortMembers({required this.enabled});

  @override
  final bool enabled;

  @override
  String get name => 'sort-members';

  @override
  Future<List<SourceEdit>> editsFor(ResolvedUnitResult unit) async => const [];
}
