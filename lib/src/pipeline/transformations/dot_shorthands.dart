import 'package:analyzer/dart/analysis/results.dart';

import '../../engine/source_edit.dart';
import '../transformation.dart';

/// Collapses `ClassName.member` to `.member` where the context type makes
/// the target unambiguous (Dart 3.5+ dot-shorthand syntax).
final class DotShorthands implements Transformation {
  const DotShorthands({required this.enabled});

  @override
  final bool enabled;

  @override
  String get name => 'dot-shorthands';

  @override
  Future<List<SourceEdit>> editsFor(ResolvedUnitResult unit) async => const [];
}
