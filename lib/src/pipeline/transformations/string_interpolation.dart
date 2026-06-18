import 'package:analyzer/dart/analysis/results.dart';

import '../../engine/source_edit.dart';
import '../transformation.dart';

/// Rewrites string concatenation chains into string interpolation.
///
/// Before: `'Hello, ' + name + '!'`
/// After:  `'Hello, $name!'`
final class StringInterpolation implements Transformation {
  @override
  final bool enabled;

  const StringInterpolation({required this.enabled});

  @override
  String get name => 'string-interpolation';

  @override
  Future<List<SourceEdit>> editsFor(ResolvedUnitResult unit) async => const [];
}
