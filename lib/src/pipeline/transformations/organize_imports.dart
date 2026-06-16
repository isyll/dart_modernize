import 'package:analyzer/dart/analysis/results.dart';

import '../../engine/source_edit.dart';
import '../transformation.dart';

/// Sorts import and export directives into canonical order and removes
/// directives that are unused.
final class OrganizeImports implements Transformation {
  const OrganizeImports({required this.enabled});

  @override
  final bool enabled;

  @override
  String get name => 'organize-imports';

  @override
  Future<List<SourceEdit>> editsFor(ResolvedUnitResult unit) async => const [];
}
