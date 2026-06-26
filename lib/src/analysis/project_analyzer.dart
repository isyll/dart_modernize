import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/file_system/overlay_file_system.dart';
import 'package:analyzer/file_system/physical_file_system.dart';

/// Loads a project for analysis and lets the pipeline rewrite files in memory.
///
/// Edits are staged in an in-memory overlay instead of being written straight to
/// disk. That lets the pipeline re-resolve and transform the project again and
/// again until it stops changing, without touching the user's files until it is
/// ready. Call [initialize] once, then alternate [resolvedUnits] with [stage] /
/// [applyStagedChanges].
final class ProjectAnalyzer {
  /// Absolute path to the project root.
  final String projectPath;

  final OverlayResourceProvider _provider = OverlayResourceProvider(
    PhysicalResourceProvider.INSTANCE,
  );

  AnalysisContextCollection? _collection;
  int _stamp = 1;

  ProjectAnalyzer(this.projectPath);

  /// Initialises the analysis context. Must be called before any other method.
  void initialize() => _collection = AnalysisContextCollection(
    includedPaths: [projectPath],
    resourceProvider: _provider,
  );

  AnalysisContextCollection get _contexts =>
      _collection ?? (throw StateError('Call initialize() first.'));

  /// Yields every resolved Dart library unit in the project, in file order.
  ///
  /// Files that cannot be resolved are skipped silently.
  Stream<ResolvedUnitResult> resolvedUnits() async* {
    for (final context in _contexts.contexts) {
      for (final filePath in context.contextRoot.analyzedFiles()) {
        if (!filePath.endsWith('.dart')) continue;
        final result = await context.currentSession.getResolvedUnit(filePath);
        if (result is ResolvedUnitResult) yield result;
      }
    }
  }

  /// Stages new [content] for [filePath] in memory and marks it for re-analysis.
  void stage(String filePath, String content) {
    _provider.setOverlay(
      filePath,
      content: content,
      modificationStamp: _stamp++,
    );
    for (final context in _contexts.contexts) {
      context.changeFile(filePath);
    }
  }

  /// Applies all staged changes so the next [resolvedUnits] call sees them.
  Future<void> applyStagedChanges() async {
    for (final context in _contexts.contexts) {
      await context.applyPendingFileChanges();
    }
  }
}
