import 'package:analyzer/dart/analysis/results.dart';
import 'package:path/path.dart' as p;

import '../analysis/project_analyzer.dart';
import '../analysis/sdk_analysis.dart';
import '../analysis/validator.dart';
import '../engine/edit_collector.dart';
import '../engine/file_filter.dart';
import '../engine/import_graph.dart';
import '../engine/source_edit.dart';
import '../output/reporter.dart';
import 'transformation.dart';

/// Runs the transform stages over a project, in memory.
///
/// Each stage resolves the project, collects every enabled pass's edits per
/// file, and stages the results in the analyzer's overlay, so the next stage
/// reads finished output. Nothing is written to disk.
///
/// With [checkEachStage], the errors of every file are compared before and
/// after each stage. A stage that adds an error has the edits behind it taken
/// back before the next stage starts: the edits of the broken file itself, or
/// of the changed files it depends on when the error lands in a caller. A file
/// that several passes edited is then retried one pass at a time, so a single
/// faulty pass does not cost the file its other changes.
final class StageRunner({
  required final ProjectAnalyzer analyzer,
  required final FileFilter filter,
  required final ImportGraph graph,
  required final Reporter reporter,
  required final bool checkEachStage,
}) {
  /// How many times a stage is re-checked after taking edits back before the
  /// remaining errors are left to the final `dart analyze` check.
  static const _maxRounds = 4;

  Future<TransformResult> run(List<List<Transformation>> stages) async {
    final originalContent = <String, String>{};
    final finalContent = <String, String>{};
    final passesByFile = <String, Set<String>>{};
    final heldBack = <String, Set<String>>{};
    final pinned = <String>{};
    var graphBuilt = false;

    for (final (index, stage) in stages.indexed) {
      final passes = stage.where((t) => t.enabled).toList();
      if (passes.isEmpty) continue;
      final watch = Stopwatch()..start();

      await analyzer.applyStagedChanges();

      // Compute each file's new content against this stage's resolution first,
      // then stage them together. Staging mid-stream would invalidate the
      // analysis session for files not yet visited this stage.
      final errorsBefore = <String, List<String>>{};
      final pending = <String, _StagedFile>{};
      await for (final unit in analyzer.resolvedUnits()) {
        if (checkEachStage) {
          errorsBefore[unit.path] = errorSignatures(unit.diagnostics);
        }
        if (!graphBuilt) graph.add(unit.path, unit.unit);
        if (filter.shouldSkip(unit.path)) continue;
        originalContent.putIfAbsent(unit.path, () => unit.content);

        // A library pinned to an older language version (`// @dart = 2.12`)
        // cannot use what the passes write, so it is left as it is.
        if (unit.libraryElement.languageVersion.effective < minimumSdk) {
          pinned.add(unit.path);
          continue;
        }

        final staged = await _editsFor(unit, passes);
        if (staged != null) pending[unit.path] = staged;
      }
      graphBuilt = true;

      for (final MapEntry(:key, :value) in pending.entries) {
        analyzer.stage(key, value.content);
      }
      if (checkEachStage && pending.isNotEmpty) {
        await _check(pending, errorsBefore, heldBack);
      }

      for (final MapEntry(:key, :value) in pending.entries) {
        if (value.applied.isEmpty) continue;
        finalContent[key] = value.content;
        (passesByFile[key] ??= <String>{}).addAll(value.applied);
      }

      reporter.verboseLine(
        'Stage ${index + 1} (${passes.map((t) => t.name).join(', ')}): '
        '${pending.length} file(s) in ${_seconds(watch.elapsed)}',
      );
    }

    final changedFiles =
        finalContent.keys
            .where((path) => finalContent[path] != originalContent[path])
            .toList()
          ..sort();

    return .new(
      filesScanned: originalContent.length,
      changedFiles: changedFiles,
      originalContent: originalContent,
      finalContent: finalContent,
      passesByFile: passesByFile,
      heldBack: heldBack,
      pinned: pinned.toList()..sort(),
    );
  }

  /// Takes back the edits of this stage that introduced an error.
  ///
  /// Mutates [pending] (the passes applied to each file) and records what was
  /// taken back in [heldBack].
  Future<void> _check(
    Map<String, _StagedFile> pending,
    Map<String, List<String>> before,
    Map<String, Set<String>> heldBack,
  ) async {
    final suspects = <String>{};
    for (var round = 0; round < _maxRounds; round++) {
      final regressed = await _regressions(before);
      if (regressed.isEmpty) break;

      final active = {
        for (final MapEntry(:key, :value) in pending.entries)
          if (value.applied.isNotEmpty) key,
      };
      final culprits = <String>{};
      for (final path in regressed) {
        if (active.contains(path)) {
          culprits.add(path);
        } else {
          culprits.addAll(graph.suspectsFor(path, active));
        }
      }
      if (culprits.isEmpty) break;

      for (final path in culprits) {
        final file = pending[path]!;
        (heldBack[path] ??= <String>{}).addAll(file.applied);
        file.applied.clear();
        analyzer.stage(path, file.before);
        suspects.add(path);
      }
    }

    // A file that several passes edited gets its passes back one at a time;
    // only the ones that keep the project error-free stay.
    for (final path in suspects) {
      final file = pending[path]!;
      if (file.editsByPass.length < 2) continue;
      for (final pass in file.editsByPass.keys) {
        file.applied.add(pass);
        analyzer.stage(path, file.content);
        if ((await _regressions(before)).isEmpty) {
          heldBack[path]!.remove(pass);
        } else {
          file.applied.remove(pass);
          analyzer.stage(path, file.content);
        }
      }
      if (heldBack[path]!.isEmpty) heldBack.remove(path);
    }
  }

  /// Runs [passes] over [unit] and returns the staged result, or null when no
  /// pass changes the file.
  Future<_StagedFile?> _editsFor(
    ResolvedUnitResult unit,
    List<Transformation> passes,
  ) async {
    final editsByPass = <String, List<SourceEdit>>{};
    for (final pass in passes) {
      final edits = await pass.editsFor(unit);
      if (edits.isNotEmpty) editsByPass[pass.name] = edits;
    }
    if (editsByPass.isEmpty) return null;
    final staged = _StagedFile(unit.content, editsByPass);
    return staged.content == unit.content ? null : staged;
  }

  /// The files whose errors grew compared to [before].
  Future<Set<String>> _regressions(Map<String, List<String>> before) async {
    await analyzer.applyStagedChanges();
    final after = await analyzer.errors();
    return {
      for (final MapEntry(:key, :value) in after.entries)
        if (newSignatures(before[key] ?? const [], value).isNotEmpty) key,
    };
  }

  static String _seconds(Duration d) =>
      '${(d.inMilliseconds / 1000).toStringAsFixed(1)}s';
}

/// Outcome of the transform stages.
final class TransformResult({
  required final int filesScanned,
  required final List<String> changedFiles,
  required final Map<String, String> originalContent,
  required final Map<String, String> finalContent,
  required final Map<String, Set<String>> passesByFile,
  required final Map<String, Set<String>> heldBack,
  required final List<String> pinned,
}) {
  /// Project-relative, forward-slash form of [path], for output.
  static String relative(String path, String projectPath) =>
      p.relative(path, from: projectPath).replaceAll(r'\', '/');
}

/// One file's edits in the current stage, grouped by pass, and which of those
/// passes are applied.
final class _StagedFile {
  _StagedFile(this.before, this.editsByPass) : applied = {...editsByPass.keys};

  /// The file's content before this stage.
  final String before;

  /// Each pass's edits, in stage order.
  final Map<String, List<SourceEdit>> editsByPass;

  /// The passes whose edits [content] includes.
  final Set<String> applied;

  /// [before] with the edits of the [applied] passes.
  String get content {
    final collector = EditCollector();
    for (final pass in applied) {
      collector.addAll(editsByPass[pass]!);
    }
    return collector.apply(before);
  }
}
