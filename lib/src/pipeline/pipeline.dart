import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:path/path.dart' as p;

import '../analysis/project_analyzer.dart';
import '../analysis/validator.dart';
import '../cli/options.dart';
import '../engine/edit_collector.dart';
import '../engine/file_filter.dart';
import '../engine/import_organizer.dart';
import '../engine/constructor_sorter.dart';
import '../engine/member_sorter.dart';
import '../engine/source_edit.dart';
import '../engine/unified_diff.dart';
import '../modernize_exception.dart';
import '../output/reporter.dart';
import 'transformation.dart';
import 'transformations.dart';

/// Orchestrates the full modernization pipeline.
///
/// Stages: **validate** -> **transform** -> **finalize**.
///
/// The transform stage runs a fixed sequence of pass groups (see
/// [buildTransformationStages] and doc/ORDERING.md). Each group is resolved once
/// and applied before the next runs, so a pass sees the finished output of every
/// group before it.
///
/// The finalize order is fixed:
///   1. `dart fix --apply`       : fixes may remove imports, so it runs first.
///   2. organize-imports         : sorts/prunes after fixes have settled.
///   3. sort-members             : reorders class members after imports are clean.
///   4. sort-constructors-first  : lifts constructors before all other members.
///   5. `dart format`            : always last so previous edits are formatted.
final class ModernizePipeline {
  final CliOptions options;
  final Reporter reporter;

  const ModernizePipeline({required this.options, required this.reporter});

  Future<void> run() async {
    // 1. Validate: fast-fail before touching the analyzer.
    await validateProject(options.path);
    reporter.validated();

    if (!buildTransformations(options).any((t) => t.enabled)) {
      reporter.nothingToDo();
      return;
    }
    final finalize = buildFinalizeTransformations(
      options,
    ).where((t) => t.enabled).toList();

    // 2. Transform: apply the structural stages to an in-memory copy.
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

    // 3. Finalize: run when structural changes happened OR finalize passes are
    //    enabled (they can fire even if no structural edits were made).
    var finalizeResult = const _FinalizeResult(counts: {}, changedPaths: {});
    if (result.changedFiles.isNotEmpty || finalize.isNotEmpty) {
      finalizeResult = await _finalize(finalize, filter);
    }

    _reportCompletion(result, finalizeResult);
  }

  /// Returns every non-excluded `.dart` file under [projectPath].
  ///
  /// Walks the tree by hand instead of `listSync(recursive: true)` so it can
  /// prune whole directories up front: hidden ones (`.dart_tool`, `.git`) and
  /// any the filter excludes (`build/`, `--exclude` paths). That keeps it out of
  /// deep build-output trees, which on Windows can exceed the path limit and
  /// throw mid-listing. A directory that cannot be listed is skipped rather than
  /// aborting the whole walk.
  List<String> _dartFiles(String projectPath, FileFilter filter) {
    final result = <String>[];
    final stack = <Directory>[Directory(projectPath)];
    while (stack.isNotEmpty) {
      final List<FileSystemEntity> entries;
      try {
        entries = stack.removeLast().listSync(followLinks: false);
      } on FileSystemException {
        continue;
      }
      for (final entity in entries) {
        if (entity is Directory) {
          if (p.basename(entity.path).startsWith('.')) continue;
          if (filter.shouldSkip(p.join(entity.path, '_.dart'))) continue;
          stack.add(entity);
        } else if (entity is File &&
            entity.path.endsWith('.dart') &&
            !filter.shouldSkip(entity.path)) {
          result.add(entity.path);
        }
      }
    }
    return result;
  }

  /// Runs `dart pub get` if the project has not yet been set up.
  ///
  /// `.dart_tool/package_config.json` is the marker that `pub get` has run;
  /// `dart fix` requires it.
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

  Future<_FinalizeResult> _finalize(
    List<FinalizeTransformation> passes,
    FileFilter filter,
  ) async {
    reporter.finalizing();

    final projectPath = options.path;
    final files = _dartFiles(projectPath, filter);
    final hasFixAll = passes.any((p) => p.name == 'fix-all');
    final hasOrganize = passes.any((p) => p.name == 'organize-imports');
    final hasSortMembers = passes.any((p) => p.name == 'sort-members');
    final hasSortConstructorsFirst = passes.any(
      (p) => p.name == 'sort-constructors-first',
    );

    final counts = <String, int>{};
    final changedPaths = <String>{};

    // Fix-all runs before import organization so that fixes which remove
    // imports are reflected before organize-imports decides what to prune.
    if (hasFixAll) {
      reporter.finalizingStep('dart fix --apply');
      await _ensurePubGet(projectPath);
      final before = _snapshot(files);
      await _runProcess(Platform.resolvedExecutable, [
        'fix',
        '--apply',
        projectPath,
      ]);
      final fixed = _changedSince(before);
      if (fixed.isNotEmpty) counts['fix-all'] = fixed.length;
      changedPaths.addAll(fixed);
    }

    // Organize-imports needs a resolved unit (pruning is driven by unused-import
    // diagnostics). Sort-members is syntactic; the two touch different regions
    // (directives vs members), so when both run their edits merge on one source.
    if (hasOrganize) {
      await _ensurePubGet(projectPath);
      final stepLabel = [
        'organize-imports',
        if (hasSortMembers) 'sort-members',
      ].join(' + ');
      reporter.finalizingStep(stepLabel);
      var organized = 0;
      var sorted = 0;
      final analyzer = ProjectAnalyzer(projectPath)..initialize();
      await for (final unit in analyzer.resolvedUnits()) {
        if (filter.shouldSkip(unit.path)) continue;
        final importEdits = organizeImportEdits(
          unit.content,
          unit.unit,
          unit.lineInfo,
          unit.diagnostics,
        );
        final memberEdits = hasSortMembers
            ? sortMemberEdits(unit.content, unit.unit, unit.lineInfo)
            : const <SourceEdit>[];
        final collector = EditCollector()
          ..addAll(importEdits)
          ..addAll(memberEdits);
        if (collector.isEmpty) continue;
        final modified = collector.apply(unit.content);
        if (modified == unit.content) continue;
        File(unit.path).writeAsStringSync(modified);
        changedPaths.add(unit.path);
        if (importEdits.isNotEmpty) organized++;
        if (memberEdits.isNotEmpty) sorted++;
      }
      if (organized > 0) counts['organize-imports'] = organized;
      if (sorted > 0) counts['sort-members'] = sorted;
    } else if (hasSortMembers) {
      reporter.finalizingStep('sort-members');
      var sorted = 0;
      for (final filePath in files) {
        final content = File(filePath).readAsStringSync();
        final parsed = parseString(
          content: content,
          path: filePath,
          throwIfDiagnostics: false,
        );
        final edits = sortMemberEdits(content, parsed.unit, parsed.lineInfo);
        if (edits.isEmpty) continue;
        final modified = (EditCollector()..addAll(edits)).apply(content);
        if (modified == content) continue;
        File(filePath).writeAsStringSync(modified);
        changedPaths.add(filePath);
        sorted++;
      }
      if (sorted > 0) counts['sort-members'] = sorted;
    }

    // sort-constructors-first reads files as left on disk by the previous steps
    // (fix-all, organize-imports, sort-members) and lifts every constructor
    // declaration before all other class members.
    if (hasSortConstructorsFirst) {
      reporter.finalizingStep('sort-constructors-first');
      var sorted = 0;
      for (final filePath in files) {
        final content = File(filePath).readAsStringSync();
        final parsed = parseString(
          content: content,
          path: filePath,
          throwIfDiagnostics: false,
        );
        final edits = sortConstructorsFirstEdits(
          content,
          parsed.unit,
          parsed.lineInfo,
        );
        if (edits.isEmpty) continue;
        final modified = (EditCollector()..addAll(edits)).apply(content);
        if (modified == content) continue;
        File(filePath).writeAsStringSync(modified);
        changedPaths.add(filePath);
        sorted++;
      }
      if (sorted > 0) counts['sort-constructors-first'] = sorted;
    }

    // dart format runs last. It does not honour `analyzer: exclude:` or
    // `--exclude`, so it is given the same filtered file list as the rest of the
    // pipeline; otherwise it would reformat excluded files. Exit 65 is a parse
    // error (syntax newer than the local SDK); the edits are already on disk, so
    // it is non-fatal.
    if (files.isNotEmpty) {
      reporter.finalizingStep('dart format');
      final before = _snapshot(files);
      // Batch so a large project cannot blow past the OS command-line limit.
      for (final batch in _batches(files, 200)) {
        await _runProcess(
          Platform.resolvedExecutable,
          ['format', ...batch],
          allowedExitCodes: {65},
        );
      }
      final formatted = _changedSince(before);
      if (formatted.isNotEmpty) counts['dart format'] = formatted.length;
      changedPaths.addAll(formatted);
    }

    return .new(counts: counts, changedPaths: changedPaths);
  }

  /// Builds the per-pass, files-changed map in canonical display order, merging
  /// the structural passes with the finalize passes.
  Map<String, int> _passCounts(_TransformResult result, _FinalizeResult fin) {
    final structural = <String, int>{};
    for (final passes in result.passesByFile.values) {
      for (final name in passes) {
        structural[name] = (structural[name] ?? 0) + 1;
      }
    }
    final all = {...structural, ...fin.counts};
    final order = [
      for (final stage in buildTransformationStages(options))
        for (final t in stage) t.name,
      'fix-all',
      'organize-imports',
      'sort-members',
      'sort-constructors-first',
      'dart format',
    ];
    return {
      for (final name in order)
        if ((all[name] ?? 0) > 0) name: all[name]!,
    };
  }

  void _reportCompletion(_TransformResult result, _FinalizeResult fin) {
    final changed = {...result.changedFiles, ...fin.changedPaths};
    reporter.completionSummary(
      scanned: result.filesScanned,
      changed: changed.length,
      passCounts: _passCounts(result, fin),
    );
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
      final stderr = '${result.stderr}'.trim();
      throw ModernizeException(
        '$executable ${args.join(' ')} failed (exit ${result.exitCode})'
        '${stderr.isNotEmpty ? '.\n$stderr' : '.'}',
      );
    }
  }

  /// Runs the fixed sequence of structural stages over the project.
  ///
  /// Edits are staged in memory; nothing is written to disk here. Every stage
  /// re-resolves the whole project, but the analyzer serves unchanged files from
  /// cache, so only files an earlier stage touched are re-analyzed. Fresh pass
  /// instances are built per stage so a pass that caches project-wide analysis
  /// (such as abstract-final-classes) sees the re-resolved code.
  Future<_TransformResult> _transform(FileFilter filter) async {
    final analyzer = ProjectAnalyzer(options.path)..initialize();
    final originalContent = <String, String>{};
    final finalContent = <String, String>{};
    final passesByFile = <String, Set<String>>{};

    for (final stage in buildTransformationStages(options)) {
      final passes = stage.where((t) => t.enabled).toList();
      if (passes.isEmpty) continue;

      await analyzer.applyStagedChanges();

      // Compute each file's new content against this stage's resolution first,
      // then stage them together. Staging mid-stream would invalidate the
      // analysis session for files not yet visited this stage.
      final pending = <String, String>{};
      await for (final unit in analyzer.resolvedUnits()) {
        if (filter.shouldSkip(unit.path)) continue;
        originalContent.putIfAbsent(unit.path, () => unit.content);

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

      for (final entry in pending.entries) {
        analyzer.stage(entry.key, entry.value);
        finalContent[entry.key] = entry.value;
      }
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
    );
  }

  /// Splits [items] into consecutive chunks of at most [size].
  static Iterable<List<T>> _batches<T>(List<T> items, int size) sync* {
    for (var i = 0; i < items.length; i += size) {
      yield items.sublist(i, i + size > items.length ? items.length : i + size);
    }
  }

  /// Paths in [before] whose on-disk content has since changed.
  static List<String> _changedSince(Map<String, String> before) => [
    for (final entry in before.entries)
      if (File(entry.key).readAsStringSync() != entry.value) entry.key,
  ];

  /// Reads the current on-disk content of each path in [files].
  static Map<String, String> _snapshot(List<String> files) => {
    for (final f in files) f: File(f).readAsStringSync(),
  };
}

/// Outcome of the finalize stage.
class _FinalizeResult {
  /// Files changed per finalize pass (`fix-all`, `organize-imports`,
  /// `sort-members`, `dart format`).
  final Map<String, int> counts;

  /// All paths the finalize stage changed.
  final Set<String> changedPaths;

  const _FinalizeResult({required this.counts, required this.changedPaths});
}

/// Outcome of the structural transform stage.
class _TransformResult {
  /// Number of non-excluded `.dart` files looked at.
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
