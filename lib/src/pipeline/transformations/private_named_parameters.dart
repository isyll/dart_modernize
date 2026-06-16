import 'package:analyzer/dart/analysis/results.dart';

import '../../engine/source_edit.dart';
import '../transformation.dart';

/// Folds verbose constructor field boilerplate into the private named
/// parameter form (`this._field`).
final class PrivateNamedParameters implements Transformation {
  @override
  final bool enabled;

  const PrivateNamedParameters({required this.enabled});

  @override
  String get name => 'private-named-parameters';

  @override
  Future<List<SourceEdit>> editsFor(ResolvedUnitResult unit) async => const [];
}
