import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:analyzer/file_system/overlay_file_system.dart';
import 'package:analyzer/file_system/physical_file_system.dart';

import 'dart_sdk.dart';

/// Loads a project for analysis and lets the pipeline rewrite files in memory.
///
/// Edits are staged in an in-memory overlay instead of being written straight to
/// disk. That lets each transform stage re-resolve and rewrite the project
/// without touching the user's files until the pipeline is ready. Call
/// [initialize] once, then alternate [resolvedUnits] with [stage] /
/// [applyStagedChanges].
///
/// A library the analyzer cannot resolve because its recursion overflows the
/// stack (a generated `operator ==` chaining hundreds of `&&` can do it under
/// the JIT) is recorded in [unresolvable] and skipped from then on, instead of
/// taking the whole run down.
final class ProjectAnalyzer(final String projectPath, {final DartSdk? sdk}) {
  final _provider = OverlayResourceProvider(PhysicalResourceProvider.INSTANCE);
  AnalysisContextCollection? _collection;

  int _stamp = 1;

  /// Files skipped because resolving their library overflowed the stack.
  final unresolvable = <String>{};

  AnalysisContextCollection get _contexts =>
      _collection ?? (throw StateError('Call initialize() first.'));

  /// Applies all staged changes so the next [resolvedUnits] call sees them.
  Future<void> applyStagedChanges() async {
    for (final context in _contexts.contexts) {
      await context.applyPendingFileChanges();
    }
  }

  /// Every analyzed `.dart` file, in file order.
  List<String> get dartFiles => [
    for (final context in _contexts.contexts)
      for (final path in context.contextRoot.analyzedFiles())
        if (path.endsWith('.dart')) path,
  ];

  /// The error-level diagnostics of every analyzed file, as `code: message`
  /// signatures keyed by path.
  ///
  /// Uses the analyzer's error cache, so a file whose dependencies did not
  /// change since it was last analyzed is not analyzed again.
  Future<Map<String, List<String>>> errors() async {
    final result = <String, List<String>>{};
    for (final context in _contexts.contexts) {
      for (final path in context.contextRoot.analyzedFiles()) {
        if (!path.endsWith('.dart') || unresolvable.contains(path)) continue;
        final SomeErrorsResult errors;
        try {
          errors = await context.currentSession.getErrors(path);
          // ignore: avoid_catching_errors, the analyzer's own recursion limit.
        } on StackOverflowError {
          unresolvable.add(path);
          continue;
        }
        if (errors is ErrorsResult) {
          result[path] = errorSignatures(errors.diagnostics);
        }
      }
    }
    return result;
  }

  /// Initialises the analysis context. Must be called before any other method.
  void initialize() => _collection = .new(
    includedPaths: [projectPath],
    resourceProvider: _provider,
    sdkPath: sdk?.path,
  );

  /// Yields every resolved Dart unit in the project, in file order.
  ///
  /// A library is resolved once and all of its units are yielded together, so a
  /// library with generated `part` files is not resolved again for each part.
  /// Files that cannot be resolved are skipped silently.
  Stream<ResolvedUnitResult> resolvedUnits() async* {
    for (final context in _contexts.contexts) {
      final seen = <String>{};
      for (final filePath in context.contextRoot.analyzedFiles()) {
        if (!filePath.endsWith('.dart') || !seen.add(filePath)) continue;
        if (unresolvable.contains(filePath)) continue;
        final SomeResolvedLibraryResult library;
        try {
          library = await context.currentSession.getResolvedLibraryContaining(
            filePath,
          );
          // ignore: avoid_catching_errors, the analyzer's own recursion limit.
        } on StackOverflowError {
          unresolvable.add(filePath);
          continue;
        }
        if (library is! ResolvedLibraryResult) {
          final unit = await context.currentSession.getResolvedUnit(filePath);
          if (unit is ResolvedUnitResult) yield unit;
          continue;
        }
        for (final unit in library.units) {
          if (unit.path != filePath && !seen.add(unit.path)) continue;
          if (!context.contextRoot.isAnalyzed(unit.path)) continue;
          yield unit;
        }
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

/// The error-level entries of [diagnostics] as `code: message` signatures.
///
/// Line and column are left out so an edit that only shifts an unrelated
/// error's position is not mistaken for a new error.
List<String> errorSignatures(Iterable<Diagnostic> diagnostics) => [
  for (final d in diagnostics)
    if (d.severity == Severity.error)
      '${d.diagnosticCode.lowerCaseName}: ${d.message}',
];
