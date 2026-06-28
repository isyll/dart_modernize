import 'dart:io';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:path/path.dart' as p;

import '../analysis/project_analyzer.dart';
import '../analysis/validator.dart';
import '../cli/options.dart';
import '../engine/edit_collector.dart';
import '../engine/file_filter.dart';
import '../engine/import_organizer.dart';
import '../engine/member_sorter.dart';
import '../engine/unified_diff.dart';
import '../modernize_exception.dart';
import '../output/reporter.dart';
import 'transformation.dart';
import 'transformations.dart';

/// Orchestrates the full modernization pipeline.
///
/// Stages: **validate** -> **transform** -> **finalize**.
///
/// The transform stage rewrites files in memory and repeats until the project
/// stops changing, so a pass can build on what an earlier pass produced (for
/// example, dot-shorthands collapsing the result of a switch rewrite).
///
/// The finalize order is fixed:
///   1. `dart fix --apply`   : fixes may remove imports, so it runs first.
///   2. organize-imports     : sorts/prunes after fixes have settled.
///   3. sort-members         : reorders class members after imports are clean.
///   4. `dart format`        : always last so previous edits are formatted.
final class ModernizePipeline {
  /// Safety cap on transform rounds. Real projects converge in a few rounds;
  /// this only guards against a pass that never settles.
  static const _maxRounds = 10;

  final CliOptions options;
  final Reporter reporter;

  const ModernizePipeline({required this.options, required this.reporter});

  Future<void> run() async {
    // 1. Validate: fast-fail before touching the analyzer.
    await validateProject(options.path);
    reporter.validated();

    final enabled = buildTransformations(options).where((t) => t.enabled);
    if (enabled.isEmpty) {
      reporter.nothingToDo();
      return;
    }
    final finalize = enabled.whereType<FinalizeTransformation>().toList();

    // 2. Transform: apply structural passes to an in-memory copy, re-resolving
    //    and re-running until nothing changes.
    reporter.resolving();
    final filter = FileFilter.forProject(
      options.path,
      cliExcludes: options.excludes,
    );
    final result = await _transform(filter);

    if (options.dryRun) {
      _reportDryRun(result);
      return;
    }

    for (final path in result.changedFiles) {
      File(path).writeAsStringSync(result.finalContent[path]!);
    }
    reporter.liveSummary(result.changedFiles.length);

    // 3. Finalize: run when structural changes happened OR finalize passes are
    //    enabled (they can fire even if no structural edits were made).
    if (result.changedFiles.isNotEmpty || finalize.isNotEmpty) {
      await _finalize(finalize, filter);
    }
  }

  /// Returns every non-excluded `.dart` file under [projectPath].
  List<String> _dartFiles(String projectPath, FileFilter filter) {
    return Directory(projectPath)
        .listSync(recursive: true)
        .whereType<File>()
        .map((f) => f.path)
        .where((fp) => fp.endsWith('.dart') && !filter.shouldSkip(fp))
        .toList();
  }

  /// Runs `dart pub get` if the project has not yet been set up.
  ///
  /// The `.dart_tool/package_config.json` file is the canonical marker that
  /// `pub get` has been run. `dart fix` requires it.
  Future<void> _ensurePubGet(String projectPath) async {
    final pkgConfig = File(
      p.join(projectPath, '.dart_tool', 'package_config.json'),
    );
    if (!pkgConfig.existsSync()) {
      await _runProcess(Platform.resolvedExecutable, [
        'pub',
        'get',
      ], workingDirectory: projectPath);
    }
  }

  Future<void> _finalize(
    List<FinalizeTransformation> passes,
    FileFilter filter,
  ) async {
    reporter.finalizing();

    final projectPath = options.path;
    final hasFixAll = passes.any((p) => p.name == 'fix-all');
    final hasOrganize = passes.any((p) => p.name == 'organize-imports');
    final hasSortMembers = passes.any((p) => p.name == 'sort-members');

    // Fix-all: dart fix --apply.
    // Runs before import organization so that fixes that remove imports are
    // reflected before organize-imports decides what to prune.
    if (hasFixAll) {
      reporter.finalizingStep('dart fix --apply');
      await _ensurePubGet(projectPath);
      await _runProcess(Platform.resolvedExecutable, [
        'fix',
        '--apply',
        projectPath,
      ]);
    }

    // Organize-imports needs a resolved unit: its pruning is driven by
    // unused-import diagnostics, so it runs pub get and resolves the project.
    // Sort-members is syntactic, so on its own it only parses each file. The
    // two passes touch different regions (directives vs members), so when both
    // run their edits are computed on the same source and merged.
    if (hasOrganize) {
      await _ensurePubGet(projectPath);
      final stepLabel = [
        'organize-imports',
        if (hasSortMembers) 'sort-members',
      ].join(' + ');
      reporter.finalizingStep(stepLabel);
      final analyzer = ProjectAnalyzer(projectPath)..initialize();
      await for (final unit in analyzer.resolvedUnits()) {
        if (filter.shouldSkip(unit.path)) continue;
        final collector = EditCollector()
          ..addAll(
            organizeImportEdits(
              unit.content,
              unit.unit,
              unit.lineInfo,
              unit.diagnostics,
            ),
          );
        if (hasSortMembers) {
          collector.addAll(
            sortMemberEdits(unit.content, unit.unit, unit.lineInfo),
          );
        }
        if (collector.isEmpty) continue;
        final modified = collector.apply(unit.content);
        if (modified != unit.content) {
          File(unit.path).writeAsStringSync(modified);
        }
      }
    } else if (hasSortMembers) {
      reporter.finalizingStep('sort-members');
      for (final filePath in _dartFiles(projectPath, filter)) {
        final content = File(filePath).readAsStringSync();
        final parsed = parseString(
          content: content,
          path: filePath,
          throwIfDiagnostics: false,
        );
        final edits = sortMemberEdits(content, parsed.unit, parsed.lineInfo);
        if (edits.isEmpty) continue;
        final modified = (EditCollector()..addAll(edits)).apply(content);
        if (modified != content) File(filePath).writeAsStringSync(modified);
      }
    }

    // dart format: always last so all previous edits end up consistently
    // formatted. `dart format` does not honour `analyzer: exclude:` or the tool's
    // own `--exclude`, so it is handed the same filtered file list the rest of
    // the pipeline uses; otherwise it would reformat excluded files (e.g. golden
    // fixtures). Exit 65 means a parse error (syntax newer than the local SDK);
    // the edits are already on disk, so that is a non-fatal warning.
    final formatTargets = _dartFiles(projectPath, filter);
    if (formatTargets.isNotEmpty) {
      reporter.finalizingStep('dart format');
      // Batch so a large project cannot blow past the OS command-line limit.
      for (final batch in _batches(formatTargets, 200)) {
        await _runProcess(Platform.resolvedExecutable, [
          'format',
          ...batch,
        ], allowedExitCodes: {65});
      }
    }
  }

  /// Splits [items] into consecutive chunks of at most [size].
  static Iterable<List<T>> _batches<T>(List<T> items, int size) sync* {
    for (var i = 0; i < items.length; i += size) {
      yield items.sublist(i, i + size > items.length ? items.length : i + size);
    }
  }

  void _reportDryRun(_TransformResult result) {
    var totalAdded = 0;
    var totalRemoved = 0;
    final passCounts = <String, int>{};

    for (final path in result.changedFiles) {
      final rel = p.relative(path, from: options.path).replaceAll(r'\', '/');
      final diffText = unifiedDiff(
        'a/$rel',
        'b/$rel',
        result.originalContent[path]!,
        result.finalContent[path]!,
      );

      var added = 0;
      var removed = 0;
      for (final line in diffText.split('\n')) {
        if (line.startsWith('+') && !line.startsWith('+++')) added++;
        if (line.startsWith('-') && !line.startsWith('---')) removed++;
      }
      totalAdded += added;
      totalRemoved += removed;

      final passes = result.passesByFile[path]!.toList();
      reporter.renderDiff(rel, passes, added, removed, diffText);
      for (final name in passes) {
        passCounts[name] = (passCounts[name] ?? 0) + 1;
      }
    }

    reporter.dryRunSummary(
      scanned: result.filesScanned,
      changed: result.changedFiles.length,
      added: totalAdded,
      removed: totalRemoved,
      passCounts: passCounts,
    );
  }

  Future<void> _runProcess(
    String executable,
    List<String> args, {
    String? workingDirectory,
    Set<int> allowedExitCodes = const {},
  }) async {
    final result = await Process.run(
      executable,
      args,
      workingDirectory: workingDirectory ?? options.path,
    );
    if (result.exitCode != 0 && !allowedExitCodes.contains(result.exitCode)) {
      throw ModernizeException(
        '$executable ${args.join(' ')} failed (exit ${result.exitCode}).\n'
        '${result.stderr}',
      );
    }
  }

  /// Runs the structural passes over the project until it reaches a fixpoint.
  ///
  /// Edits are staged in memory; nothing is written to disk here. The first
  /// round scans every file; later rounds only revisit files that changed in the
  /// round before, since a file that stopped changing has nothing left to do.
  /// Fresh pass instances are built each round so passes that cache project-wide
  /// analysis (such as abstract-final-classes) see the re-resolved code.
  Future<_TransformResult> _transform(FileFilter filter) async {
    final analyzer = ProjectAnalyzer(options.path)..initialize();
    final originalContent = <String, String>{};
    final finalContent = <String, String>{};
    final passesByFile = <String, Set<String>>{};
    var filesScanned = 0;
    var toVisit = <String>{};

    for (var round = 0; round < _maxRounds; round++) {
      await analyzer.applyStagedChanges();
      final passes = buildTransformations(
        options,
      ).where((t) => t.enabled && t is! FinalizeTransformation).toList();

      // Compute every target file's new content against this round's resolution
      // first, then stage them together. Staging mid-stream would invalidate the
      // analysis session and skip files not yet visited this round.
      final pending = <String, String>{};
      final units = round == 0
          ? analyzer.resolvedUnits()
          : _resolveEach(analyzer, toVisit);
      await for (final unit in units) {
        if (filter.shouldSkip(unit.path)) continue;
        if (round == 0) {
          filesScanned++;
          originalContent[unit.path] = unit.content;
        }

        final collector = EditCollector();
        final touched = <String>[];
        for (final pass in passes) {
          final edits = await pass.editsFor(unit);
          if (edits.isNotEmpty) touched.add(pass.name);
          collector.addAll(edits);
        }
        if (collector.isEmpty) continue;

        final modified = collector.apply(unit.content);
        if (modified == unit.content) continue;

        pending[unit.path] = modified;
        (passesByFile[unit.path] ??= <String>{}).addAll(touched);
      }

      if (pending.isEmpty) break;
      for (final entry in pending.entries) {
        analyzer.stage(entry.key, entry.value);
        finalContent[entry.key] = entry.value;
      }
      toVisit = pending.keys.toSet();
    }

    final changedFiles =
        finalContent.keys
            .where((path) => finalContent[path] != originalContent[path])
            .toList()
          ..sort();

    return _TransformResult(
      filesScanned: filesScanned,
      changedFiles: changedFiles,
      originalContent: originalContent,
      finalContent: finalContent,
      passesByFile: passesByFile,
    );
  }

  /// Resolves each path in [paths], skipping any that no longer resolve.
  Stream<ResolvedUnitResult> _resolveEach(
    ProjectAnalyzer analyzer,
    Set<String> paths,
  ) async* {
    for (final path in paths) {
      final unit = await analyzer.resolve(path);
      if (unit != null) yield unit;
    }
  }
}

/// Outcome of the structural transform stage.
class _TransformResult {
  /// Number of files looked at (counted on the first round).
  final int filesScanned;

  /// Paths whose final content differs from disk, sorted.
  final List<String> changedFiles;

  /// On-disk content of each scanned file, keyed by path.
  final Map<String, String> originalContent;

  /// Final in-memory content of each changed file, keyed by path.
  final Map<String, String> finalContent;

  /// The passes that edited each changed file, keyed by path.
  final Map<String, Set<String>> passesByFile;

  _TransformResult({
    required this.filesScanned,
    required this.changedFiles,
    required this.originalContent,
    required this.finalContent,
    required this.passesByFile,
  });
}
