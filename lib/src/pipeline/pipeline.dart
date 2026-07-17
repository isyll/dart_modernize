import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:path/path.dart' as p;

import '../analysis/project_analyzer.dart';
import '../analysis/validator.dart';
import '../cli/options.dart';
import '../engine/constructor_sorter.dart';
import '../engine/edit_collector.dart';
import '../engine/file_filter.dart';
import '../engine/import_organizer.dart';
import '../engine/member_sorter.dart';
import '../engine/source_edit.dart';
import '../engine/text_shape.dart';
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
  const ModernizePipeline({required this.options, required this.reporter});
  final CliOptions options;

  final Reporter reporter;

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

    final willChange = result.changedFiles.isNotEmpty || finalize.isNotEmpty;

    // Record each scanned file's original line ending and BOM before anything
    // is written, so the edits can be written back in the same shape. `dart
    // format` (and older `dart fix`) would otherwise rewrite the whole file as
    // LF with no BOM, turning a one-line edit into a whole-file diff.
    final shapes = willChange
        ? _captureShapes(filter)
        : const <String, TextShape>{};

    // Capture the pre-edit error baseline before touching disk, so the verify
    // step can tell an error the run introduced from one that was already there.
    var baseline = const <String, List<String>>{};
    if (options.verify && willChange) {
      await _ensurePubGet(options.path);
      baseline = await _analyzeErrors();
    }

    for (final path in result.changedFiles) {
      File(path).writeAsStringSync(result.finalContent[path]!);
    }

    // 3. Finalize: run when structural changes happened OR finalize passes are
    //    enabled (they can fire even if no structural edits were made).
    var finalizeResult = const _FinalizeResult(counts: {}, changedPaths: {});
    if (willChange) {
      finalizeResult = await _finalize(finalize, filter);
    }

    // 4. Verify: re-analyze and undo any changed file that gained an error, so
    //    a run can never leave a file on disk that no longer compiles.
    var reverted = const <String, List<String>>{};
    if (options.verify && willChange) {
      reverted = await _verify(result, finalizeResult, baseline);
    }

    // 5. Restore each scanned file's original line ending and BOM, undoing any
    //    normalization the finalize step applied. Runs over every scanned file
    //    (not just the reported changes) because `dart format` rewrites files
    //    without the change tracker seeing a BOM-only difference, and after the
    //    verify revert so a restored file matches its original byte for byte.
    if (willChange) _restoreShapes(shapes);

    if (reverted.isNotEmpty) {
      reporter.verificationReverted(reverted);
      final noun = reverted.length == 1 ? 'file' : 'files';
      throw ModernizeException(
        'Reverted ${reverted.length} $noun that would no longer compile. '
        'Re-run with --no-verify to keep the changes anyway.',
      );
    }

    _reportCompletion(result, finalizeResult);
  }

  /// Runs `dart analyze --format=machine` and returns the error-level
  /// diagnostics keyed by canonicalized file path.
  ///
  /// Each value is a list of `code: message` signatures; line and column are
  /// left out so an edit that only shifts an unrelated error's position is not
  /// mistaken for a new error. `dart analyze` exits non-zero whenever it finds
  /// issues, so its exit code is ignored and stdout is parsed instead.
  Future<Map<String, List<String>>> _analyzeErrors() async {
    final result = await Process.run(Platform.resolvedExecutable, [
      'analyze',
      '--format=machine',
      options.path,
    ], workingDirectory: options.path);

    final errors = <String, List<String>>{};
    for (final line in const LineSplitter().convert('${result.stdout}')) {
      // SEVERITY|TYPE|CODE|FILE|LINE|COLUMN|LENGTH|MESSAGE, with \ | and
      // newlines backslash-escaped inside fields.
      final parts = line.split('|');
      if (parts.length < 8 || parts[0] != 'ERROR') continue;
      final file = p.canonicalize(_unescapeMachine(parts[3]));
      final message = _unescapeMachine(parts.sublist(7).join('|'));
      (errors[file] ??= <String>[]).add('${parts[2]}: $message');
    }
    return errors;
  }

  /// Reads each non-excluded file's original line-ending and BOM shape from
  /// disk, keyed by canonical path.
  ///
  /// Must run before anything is written. Covers every scanned file, not just
  /// the ones about to change, because the finalize `dart format` step rewrites
  /// them all and any of them can lose its shape.
  Map<String, TextShape> _captureShapes(FileFilter filter) {
    final shapes = <String, TextShape>{};
    for (final path in _dartFiles(options.path, filter)) {
      try {
        shapes[p.canonicalize(path)] = .ofBytes(File(path).readAsBytesSync());
      } on FileSystemException {
        continue;
      }
    }
    return shapes;
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
    final stack = <Directory>[.new(projectPath)];
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
      // `dart fix --apply` takes the project root, not a file list, so it also
      // sees files the rest of the pipeline excludes. Snapshot them first and
      // restore any it touches, so an excluded file stays byte for byte
      // identical.
      final excluded = _fixApplyScope(
        projectPath,
      ).where(filter.shouldSkip).toList();
      final excludedBefore = _snapshot(excluded);
      final before = _snapshot(files);
      await _runProcess(Platform.resolvedExecutable, [
        'fix',
        '--apply',
        projectPath,
      ]);
      _restore(excludedBefore);
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

  /// Every `.dart` file under [projectPath], excluded ones included, so the
  /// caller can snapshot and later restore them.
  ///
  /// Unlike the other finalize steps, `dart fix --apply` is handed the project
  /// root rather than a file list, so it reaches files the pipeline means to
  /// skip. This walk therefore keeps the excluded files (the caller narrows the
  /// result with [FileFilter.shouldSkip]) instead of dropping them the way
  /// [_dartFiles] does. Hidden directories and `build/` are still pruned: they
  /// hold tool state and regenerated output the tool never promises to
  /// preserve, and a deep `build/` tree can exceed the Windows path limit
  /// mid-walk.
  List<String> _fixApplyScope(String projectPath) {
    final result = <String>[];
    final stack = <Directory>[.new(projectPath)];
    while (stack.isNotEmpty) {
      final List<FileSystemEntity> entries;
      try {
        entries = stack.removeLast().listSync(followLinks: false);
      } on FileSystemException {
        continue;
      }
      for (final entity in entries) {
        if (entity is Directory) {
          final name = p.basename(entity.path);
          if (name.startsWith('.') || name == 'build') continue;
          stack.add(entity);
        } else if (entity is File && entity.path.endsWith('.dart')) {
          result.add(entity.path);
        }
      }
    }
    return result;
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

  /// Rewrites each file in [shapes] back into its original line-ending and BOM
  /// shape (or the forced [CliOptions.lineEndings] when not auto).
  ///
  /// In auto mode a plain-LF file needs no work, so it is skipped without a
  /// read. Every other file is read, re-encoded, and written back only when the
  /// bytes actually differ, so unchanged files keep their timestamp.
  void _restoreShapes(Map<String, TextShape> shapes) {
    final target = options.lineEndings;
    for (final entry in shapes.entries) {
      if (target == .auto && entry.value.isPlainLf) continue;
      final path = entry.key;
      final String current;
      try {
        current = File(path).readAsStringSync();
      } on FileSystemException {
        continue;
      }
      final restored = entry.value.apply(current, target);
      if (restored != current) File(path).writeAsStringSync(restored);
    }
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

  /// Re-analyzes the project and reverts any changed file that gained an error.
  ///
  /// Returns the reverted files as project-relative path -> the new error
  /// signatures; empty when everything still compiles. Files that still compile
  /// are left as edited. `dart analyze` is used (not the in-process analyzer) so
  /// the verdict matches exactly what the user's SDK reports, including
  /// experiment-gated syntax the in-process analyzer would accept.
  Future<Map<String, List<String>>> _verify(
    _TransformResult result,
    _FinalizeResult finalize,
    Map<String, List<String>> baseline,
  ) async {
    final changed = {...result.changedFiles, ...finalize.changedPaths};
    if (changed.isEmpty) return const {};

    reporter.verifying();
    final current = await _analyzeErrors();
    final reverted = <String, List<String>>{};

    for (final path in changed) {
      final key = p.canonicalize(path);
      final newErrors = _newErrors(
        baseline[key] ?? const [],
        current[key] ?? const [],
      );
      if (newErrors.isEmpty) continue;

      // Restore the pre-run content. This is the analyzer's view (a leading
      // BOM is stripped on read); the later _restoreShapes pass puts the
      // original line ending and BOM back, so the file ends up byte identical.
      File(path).writeAsStringSync(result.originalContent[path]!);
      final rel = p.relative(path, from: options.path).replaceAll(r'\', '/');
      reverted[rel] = newErrors;
    }

    return reverted;
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

  /// The error signatures in [after] not present in [before].
  ///
  /// Matched as a multiset, so a pre-existing error is consumed once and only
  /// genuinely new errors are returned.
  static List<String> _newErrors(List<String> before, List<String> after) {
    final remaining = [...before];
    final added = <String>[];
    for (final signature in after) {
      final index = remaining.indexOf(signature);
      if (index >= 0) {
        remaining.removeAt(index);
      } else {
        added.add(signature);
      }
    }
    return added;
  }

  /// Rewrites any path in [snapshot] whose on-disk content no longer matches
  /// back to its snapshotted content.
  static void _restore(Map<String, String> snapshot) {
    for (final entry in snapshot.entries) {
      if (File(entry.key).readAsStringSync() != entry.value) {
        File(entry.key).writeAsStringSync(entry.value);
      }
    }
  }

  /// Reads the current on-disk content of each path in [files].
  static Map<String, String> _snapshot(List<String> files) => {
    for (final f in files) f: File(f).readAsStringSync(),
  };

  /// Reverses `dart analyze --format=machine` field escaping, where a
  /// backslash escapes the next character and an escaped `n` is a newline.
  /// Recovers the original file paths and messages in one pass.
  static String _unescapeMachine(String field) {
    final buffer = StringBuffer();
    for (var i = 0; i < field.length; i++) {
      if (field[i] == '\\' && i + 1 < field.length) {
        final next = field[++i];
        buffer.write(next == 'n' ? '\n' : next);
      } else {
        buffer.write(field[i]);
      }
    }
    return buffer.toString();
  }
}

/// Outcome of the finalize stage.
class _FinalizeResult {
  const _FinalizeResult({required this.counts, required this.changedPaths});

  /// Files changed per finalize pass (`fix-all`, `organize-imports`,
  /// `sort-members`, `dart format`).
  final Map<String, int> counts;

  /// All paths the finalize stage changed.
  final Set<String> changedPaths;
}

/// Outcome of the structural transform stage.
class _TransformResult {
  _TransformResult({
    required this.filesScanned,
    required this.changedFiles,
    required this.originalContent,
    required this.finalContent,
    required this.passesByFile,
  });

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
}
