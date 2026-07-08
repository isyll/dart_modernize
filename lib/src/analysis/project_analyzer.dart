import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/file_system/overlay_file_system.dart';
import 'package:analyzer/file_system/physical_file_system.dart';

/// Loads a project for analysis and lets the pipeline rewrite files in memory.
///
/// Edits are staged in an in-memory overlay instead of being written straight to
/// disk. That lets each transform stage re-resolve and rewrite the project
/// without touching the user's files until the pipeline is ready. Unchanged
/// files are served from the analyzer's cache, so re-resolving the whole project
/// between stages only re-analyzes the files an earlier stage changed. Call
/// [initialize] once, then alternate [resolvedUnits] with [stage] /
/// [applyStagedChanges].
final class ProjectAnalyzer {
  ProjectAnalyzer(this.projectPath);

  /// Absolute path to the project root.
  final String projectPath;

  final _provider = OverlayResourceProvider(PhysicalResourceProvider.INSTANCE);
  AnalysisContextCollection? _collection;

  int _stamp = 1;

  AnalysisContextCollection get _contexts =>
      _collection ?? (throw StateError('Call initialize() first.'));

  /// Applies all staged changes so the next [resolvedUnits] call sees them.
  Future<void> applyStagedChanges() async {
    for (final context in _contexts.contexts) {
      await context.applyPendingFileChanges();
    }
  }

  /// Initialises the analysis context. Must be called before any other method.
  void initialize() => _collection = .new(
    includedPaths: [projectPath],
    resourceProvider: _provider,
  );

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
}
