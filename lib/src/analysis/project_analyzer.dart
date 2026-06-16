import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';

/// Thin wrapper around [AnalysisContextCollection] for a single project path.
///
/// Call [initialize] once, then iterate [resolvedUnits].
final class ProjectAnalyzer {
  /// Absolute path to the project root.
  final String projectPath;

  AnalysisContextCollection? _collection;

  ProjectAnalyzer(this.projectPath);

  /// Initialises the analysis context. Must be called before [resolvedUnits].
  void initialize() {
    _collection = .new(includedPaths: [projectPath]);
  }

  /// Yields every resolved Dart library unit in the project, in file order.
  ///
  /// Files that cannot be resolved are skipped silently.
  Stream<ResolvedUnitResult> resolvedUnits() async* {
    final collection = _collection;
    if (collection == null) {
      throw StateError('Call initialize() before resolvedUnits().');
    }

    for (final context in collection.contexts) {
      for (final filePath in context.contextRoot.analyzedFiles()) {
        if (!filePath.endsWith('.dart')) continue;
        final result = await context.currentSession.getResolvedUnit(filePath);
        if (result is ResolvedUnitResult) yield result;
      }
    }
  }
}
