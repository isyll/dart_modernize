import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../analysis/dart_sdk.dart';
import '../analysis/project_analyzer.dart';
import '../analysis/sdk_analysis.dart';
import '../analysis/sdk_upgrade.dart';
import '../analysis/validator.dart';
import '../cli/options.dart';
import '../engine/constructor_sorter.dart';
import '../engine/edit_collector.dart';
import '../engine/file_filter.dart';
import '../engine/import_graph.dart';
import '../engine/import_organizer.dart';
import '../engine/member_sorter.dart';
import '../engine/source_edit.dart';
import '../engine/text_shape.dart';
import '../engine/unified_diff.dart';
import '../modernize_exception.dart';
import '../output/reporter.dart';
import '../vcs/git_worktree.dart';
import 'project_verifier.dart';
import 'run_backup.dart';
import 'stage_runner.dart';
import 'transformation.dart';
import 'transformations.dart';

/// Runs the whole thing: validate, then transform, then finalize, then verify.
///
/// Transform runs the pass groups from [buildTransformationStages] in order,
/// applying each group before the next starts, so a pass always sees finished
/// output. See doc/ORDERING.md.
///
/// Finalize order is fixed: `dart fix --apply` first (its fixes can remove
/// imports), then organize-imports, sort-members, sort-constructors-first, and
/// `dart format` last, over the files the run changed.
///
/// `--dry-run` and `--check` take the same steps in memory, so a preview shows
/// what a real run would write. Only `dart fix` needs files on disk; a preview
/// names the files it would change instead of diffing them.
final class const ModernizePipeline({
  required final CliOptions options,
  required final Reporter reporter,
}) {
  bool get _preview => options.dryRun || options.check;

  Future<void> run() async {
    final backup = RunBackup(options.path);
    if (options.restore) {
      if (!backup.exists) {
        reporter.nothingToRestore();
      } else {
        reporter.restored(backup.restore());
      }
      return;
    }
    if (backup.exists) {
      throw const ModernizeException(
        'A previous run was interrupted before it finished, and its copies of '
        'the original files are still in .dart_tool/dart_modernize/backup. Run '
        'dart_modernize --restore to put them back first.',
      );
    }
    if (options.upgradeSdk && _preview) {
      throw const ModernizeException(
        '--upgrade-sdk edits pubspec.yaml, so it cannot be combined with '
        '--dry-run or --check.',
      );
    }

    // Refuse to run on a dirty Git tree unless the user opts out, so the tool's
    // edits land in their own reviewable diff. Skipped in the preview modes
    // (--dry-run/--check write nothing) and when the target is not in a repo.
    if (!_preview && !options.allowDirty) _ensureCleanWorktree();

    final sdk = DartSdk.resolve();
    if (options.upgradeSdk) await _upgradeSdk(sdk);

    // 1. Validate: fast-fail before touching the analyzer.
    await validateProject(options.path);
    reporter.validated();

    if (!buildTransformations(options).any((t) => t.enabled)) {
      reporter.nothingToDo();
      return;
    }

    final finalize = buildFinalizeTransformations(options)
        .where((t) => t.enabled)
        .toList();
    final filter = FileFilter.forProject(
      options.path,
      cliExcludes: options.excludes,
    );

    // The pre-edit `dart analyze` baseline reads the files before anything is
    // written, so it runs alongside the transform instead of after it.
    SdkAnalysis? baseline;
    if (!_preview && options.verify) {
      await _ensurePubGet(sdk);
      baseline = await SdkAnalysis.start(sdk, options.path);
    }

    // 2. Transform: apply the structural stages to an in-memory copy.
    reporter.resolving();
    final analyzer = ProjectAnalyzer(options.path, sdk: sdk)..initialize();
    final graph = ImportGraph(options.path, _packageName());
    final TransformResult result;
    try {
      result = await StageRunner(
        analyzer: analyzer,
        filter: filter,
        graph: graph,
        reporter: reporter,
        checkEachStage: options.verify,
      ).run(buildTransformationStages(options));
    } on Object {
      baseline?.cancel();
      rethrow;
    }
    _reportSkipped(result, analyzer);

    if (_preview) {
      await _runPreview(result, analyzer, finalize, filter, sdk);
      return;
    }

    final willChange = result.changedFiles.isNotEmpty || finalize.isNotEmpty;
    if (!willChange) {
      baseline?.cancel();
      _reportCompletion(result, const _FinalizeResult(), const {});
      return;
    }

    // Record each scanned file's original line ending and BOM before anything
    // is written, so the edits can be written back in the same shape. `dart
    // format` (and older `dart fix`) would otherwise rewrite the whole file as
    // LF with no BOM, turning a one-line edit into a whole-file diff.
    final shapes = _captureShapes(filter);
    final baselineDiagnostics = await baseline?.result;

    // A crash from here on would leave files half written, so copies of every
    // file the run may touch go to disk first, and any failure puts them back.
    backup.save([
      ...{..._dartFiles(filter), if (options.fixAll) ..._fixApplyScope()},
    ]);
    var finished = false;
    final _FinalizeResult finalized;
    var verified = const VerifyOutcome();
    try {
      for (final path in result.changedFiles) {
        File(path).writeAsStringSync(result.finalContent[path]!);
      }

      // 3. Finalize.
      finalized = await _finalize(result, analyzer, finalize, filter, sdk);

      // 4. Verify: re-analyze the whole project and undo the changes behind
      //    any new error, so a run never leaves code that no longer compiles.
      final changed = {...result.changedFiles, ...finalized.changedPaths};
      if (options.verify && baselineDiagnostics != null && changed.isNotEmpty) {
        reporter.verifying();
        verified =
            await ProjectVerifier(
              analyze: () => analyzeWithSdk(sdk, options.path),
              graph: graph,
              projectPath: options.path,
            ).verify(
              baseline: baselineDiagnostics,
              changed: changed,
              originals: result.originalContent,
              files: analyzer.dartFiles,
            );
      }

      // 5. Restore each changed file's original line ending and BOM, undoing
      //    any normalization the finalize step applied, after the verify
      //    revert so a restored file matches its original byte for byte.
      _restoreShapes({
        for (final path in {...result.changedFiles, ...finalized.changedPaths})
          p.canonicalize(path): ?shapes[p.canonicalize(path)],
      });
      finished = true;
    } finally {
      if (!finished) backup.restore();
      backup.discard();
    }

    _reportCompletion(result, finalized, verified.reverted.keys.toSet());
    reporter.newDiagnostics(verified.newDiagnostics);
    reporter.unexplainedErrors(verified.unexplained);
    if (verified.reverted.isNotEmpty) {
      reporter.verificationReverted(
        {
          for (final MapEntry(:key, :value) in verified.reverted.entries)
            _relative(key): value,
        },
        passes: {
          for (final path in verified.reverted.keys)
            _relative(path): {
              ...?result.passesByFile[path],
              ...?finalized.stepsByFile[path],
            },
        },
      );
      throw const PartialSuccessException();
    }
    if (verified.unexplained.isNotEmpty) {
      throw const ModernizeException(
        'The run left errors it could not undo. Review them with dart analyze.',
      );
    }
  }

  /// Applies the lints in [CliOptions.lintFixes] through `dart fix`, whether or
  /// not the project enables them, and returns the files it changed.
  ///
  /// `dart fix` only fixes the lints the analysis options turn on, so the
  /// project's `analysis_options.yaml` is swapped for one that includes the
  /// original and adds the lints, and put back afterwards.
  Future<List<String>> _applyLintFixes(DartSdk sdk, List<String> files) async {
    final optionsFile = File(p.join(options.path, 'analysis_options.yaml'));
    final original = optionsFile.existsSync()
        ? optionsFile.readAsStringSync()
        : null;
    final baseDir = p.join(options.path, '.dart_tool', 'dart_modernize');
    final baseFile = File(p.join(baseDir, 'analysis_options.base.yaml'));
    final before = _snapshot(files);
    try {
      if (original != null) {
        baseFile
          ..parent.createSync(recursive: true)
          ..writeAsStringSync(_relocateIncludes(original));
      }
      optionsFile.writeAsStringSync(
        [
          if (original != null)
            'include: .dart_tool/dart_modernize/analysis_options.base.yaml',
          'linter:',
          '  rules:',
          for (final lint in options.lintFixes) '    $lint: true',
          '',
        ].join('\n'),
      );
      await _runProcess(sdk.dartExecutable, [
        'fix',
        '--apply',
        '--code=${options.lintFixes.join(',')}',
        options.path,
      ]);
    } finally {
      if (original == null) {
        if (optionsFile.existsSync()) optionsFile.deleteSync();
      } else {
        optionsFile.writeAsStringSync(original);
      }
      if (baseFile.existsSync()) baseFile.deleteSync();
    }
    return _changedSince(before);
  }

  /// Reads each non-excluded file's original line-ending and BOM shape from
  /// disk, keyed by canonical path. Must run before anything is written.
  Map<String, TextShape> _captureShapes(FileFilter filter) {
    final shapes = <String, TextShape>{};
    for (final path in _dartFiles(filter)) {
      try {
        shapes[p.canonicalize(path)] = .ofBytes(File(path).readAsBytesSync());
      } on FileSystemException {
        continue;
      }
    }
    return shapes;
  }

  /// Returns every non-excluded `.dart` file under the project.
  ///
  /// Walks the tree by hand instead of `listSync(recursive: true)` so it can
  /// prune whole directories up front: hidden ones (`.dart_tool`, `.git`) and
  /// any the filter excludes (`build/`, `--exclude` paths). That keeps it out of
  /// deep build-output trees, which on Windows can exceed the path limit and
  /// throw mid-listing. A directory that cannot be listed is skipped rather than
  /// aborting the whole walk.
  List<String> _dartFiles(FileFilter filter) {
    final result = <String>[];
    final stack = <Directory>[.new(options.path)];
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

  /// Runs `dart fix --dry-run` and returns the project-relative files it would
  /// change, or an empty list when the project has no package config yet (a
  /// preview never runs `pub get`, which would write to the project).
  Future<List<String>> _dartFixPreview(DartSdk sdk) async {
    final config = File(
      p.join(options.path, '.dart_tool', 'package_config.json'),
    );
    if (!config.existsSync()) return const [];
    final result = await Process.run(sdk.dartExecutable, [
      'fix',
      '--dry-run',
      options.path,
    ], workingDirectory: options.path);
    final files = <String>[];
    for (final line in const LineSplitter().convert('${result.stdout}')) {
      if (line.isEmpty || line.startsWith(' ')) continue;
      final trimmed = line.trim();
      if (!trimmed.endsWith('.dart')) continue;
      files.add(trimmed.replaceAll(r'\', '/'));
    }
    return files;
  }

  /// Throws when the target sits in a Git work tree with uncommitted changes to
  /// tracked files, so the tool's edits do not tangle with the user's own.
  ///
  /// A no-op when git is missing or the target is not in a repository (nothing
  /// to protect), and when `--allow-dirty` was passed (checked by the caller).
  void _ensureCleanWorktree() {
    final dirty = uncommittedTrackedChanges(options.path);
    if (dirty.isEmpty) return;
    final noun = dirty.length == 1 ? 'change' : 'changes';
    throw ModernizeException(
      'The Git working tree has ${dirty.length} uncommitted $noun to tracked '
      'files. Commit or stash them so the modernization lands in its own diff, '
      'or re-run with --allow-dirty.',
    );
  }

  /// Runs `dart pub get` if the project has not yet been set up.
  ///
  /// `.dart_tool/package_config.json` is the marker that `pub get` has run;
  /// `dart fix` and `dart analyze` require it.
  Future<void> _ensurePubGet(DartSdk sdk) async {
    final pkgConfig = File(
      p.join(options.path, '.dart_tool', 'package_config.json'),
    );
    if (!pkgConfig.existsSync()) {
      await _runProcess(sdk.dartExecutable, ['pub', 'get']);
    }
  }

  /// Runs the finalize steps over the files on disk and returns what changed.
  ///
  /// The structural edits are already written. The analyzer from the transform
  /// stages is reused for organize-imports, with every file `dart fix` touched
  /// staged again, so it does not start cold.
  Future<_FinalizeResult> _finalize(
    TransformResult result,
    ProjectAnalyzer analyzer,
    List<FinalizeTransformation> passes,
    FileFilter filter,
    DartSdk sdk,
  ) async {
    final names = {for (final pass in passes) pass.name};
    final files = _dartFiles(filter);
    final changedPaths = <String>{};
    final stepsByFile = <String, Set<String>>{};
    void record(String step, Iterable<String> paths) {
      for (final path in paths) {
        changedPaths.add(path);
        (stepsByFile[path] ??= <String>{}).add(step);
      }
    }

    // `dart fix --apply` takes the project root, not a file list, so it also
    // sees files the rest of the pipeline excludes. Those are snapshotted
    // first and put back after each run, so an excluded file stays byte for
    // byte identical.
    final hasFixAll = names.contains('fix-all');
    final excludedBefore = hasFixAll || options.lintFixes.isNotEmpty
        ? _snapshot(_fixApplyScope().where(filter.shouldSkip).toList())
        : const <String, String>{};
    Future<List<String>> fixAll() async {
      final before = _snapshot(files);
      await _runProcess(sdk.dartExecutable, ['fix', '--apply', options.path]);
      _restore(excludedBefore);
      return _changedSince(before);
    }

    reporter.finalizing();

    // Fix-all runs before import organization so that fixes which remove
    // imports are reflected before organize-imports decides what to prune.
    if (hasFixAll || options.lintFixes.isNotEmpty) {
      await _ensurePubGet(sdk);
      if (hasFixAll) {
        reporter.finalizingStep('dart fix --apply');
        record('fix-all', await fixAll());
      }
      if (options.lintFixes.isNotEmpty) {
        reporter.finalizingStep('lint fixes: ${options.lintFixes.join(', ')}');
        final fixed = await _applyLintFixes(sdk, files);
        _restore(excludedBefore);
        record('lint-fixes', fixed);
      }
      for (final path in changedPaths) {
        analyzer.stage(path, File(path).readAsStringSync());
      }
    }

    // Organize-imports needs a resolved unit (pruning is driven by unused-import
    // diagnostics). Sort-members is syntactic; the two touch different regions
    // (directives vs members), so when both run their edits merge on one source.
    final hasOrganize = names.contains('organize-imports');
    final hasSortMembers = names.contains('sort-members');
    if (hasOrganize || hasSortMembers) {
      reporter.finalizingStep(
        [
          if (hasOrganize) 'organize-imports',
          if (hasSortMembers) 'sort-members',
        ].join(' + '),
      );
      final edited = await _organize(
        analyzer,
        filter,
        organize: hasOrganize,
        sortMembers: hasSortMembers,
        read: (path) => File(path).readAsStringSync(),
        pinned: result.pinned.toSet(),
      );
      for (final MapEntry(key: path, value: change) in edited.entries) {
        File(path).writeAsStringSync(change.content);
      }
      record('organize-imports', [
        for (final MapEntry(:key, :value) in edited.entries)
          if (value.organized) key,
      ]);
      record('sort-members', [
        for (final MapEntry(:key, :value) in edited.entries)
          if (value.sorted) key,
      ]);
    }

    // sort-constructors-first reads files as left on disk by the previous steps
    // and lifts every constructor declaration before all other class members.
    if (names.contains('sort-constructors-first')) {
      reporter.finalizingStep('sort-constructors-first');
      final sorted = <String>[];
      final pinned = result.pinned.toSet();
      for (final path in files) {
        if (pinned.contains(path)) continue;
        final content = File(path).readAsStringSync();
        final modified = _sortConstructorsFirst(path, content);
        if (modified == null) continue;
        File(path).writeAsStringSync(modified);
        sorted.add(path);
      }
      record('sort-constructors-first', sorted);
    }

    // dart format runs last, over the files this run changed and nothing else:
    // a project formatted to another width, or not formatted at all, keeps its
    // own layout everywhere the tool did not edit.
    final toFormat = {...result.changedFiles, ...changedPaths}.toList()..sort();
    if (options.format && toFormat.isNotEmpty) {
      reporter.finalizingStep('dart format');
      final before = _snapshot(toFormat);
      await _format(sdk, toFormat);
      final formatted = _changedSince(before);
      record('dart format', formatted);

      // Formatting can break a line in a way a lint the project enables then
      // flags, such as an `if` body moving under its condition without braces.
      // dart fix runs once more over that result and its changes are formatted
      // too, so a second run of the tool finds nothing left to do.
      if (hasFixAll && formatted.isNotEmpty) {
        final refixed = await fixAll();
        if (refixed.isNotEmpty) {
          record('fix-all', refixed);
          final beforeFormat = _snapshot(refixed);
          await _format(sdk, refixed);
          record('dart format', _changedSince(beforeFormat));
        }
      }
    }

    final counts = <String, int>{};
    for (final steps in stepsByFile.values) {
      for (final step in steps) {
        counts[step] = (counts[step] ?? 0) + 1;
      }
    }
    return .new(
      counts: counts,
      changedPaths: changedPaths,
      stepsByFile: stepsByFile,
    );
  }

  /// Every `.dart` file under the project, excluded ones included, so the
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
  List<String> _fixApplyScope() {
    final result = <String>[];
    final stack = <Directory>[.new(options.path)];
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

  /// Runs `dart format` over [files], in batches so a large project cannot
  /// blow past the OS command-line limit. Exit 65 is a parse error (syntax
  /// newer than the local SDK); the edits are already in place, so it is
  /// non-fatal.
  Future<void> _format(DartSdk sdk, List<String> files) async {
    for (final batch in _batches(files, 200)) {
      await _runProcess(
        sdk.dartExecutable,
        [
          'format',
          if (options.lineLength case final width?) '--page-width=$width',
          ...batch,
        ],
        allowedExitCodes: {65},
      );
    }
  }

  /// Formats [contents] (path to text) the way [_format] would format those
  /// files, without touching them: the text goes to a scratch copy under
  /// `.dart_tool`, where `dart format` still finds the project's language
  /// version and page width.
  Future<Map<String, String>> _formatInMemory(
    DartSdk sdk,
    Map<String, String> contents,
  ) async {
    if (contents.isEmpty) return contents;
    final scratch = Directory(
      p.join(options.path, '.dart_tool', 'dart_modernize', 'preview'),
    );
    final copies = <String, String>{};
    try {
      for (final MapEntry(:key, :value) in contents.entries) {
        final copy = p.join(scratch.path, p.relative(key, from: options.path));
        File(copy)
          ..parent.createSync(recursive: true)
          ..writeAsStringSync(value);
        copies[key] = copy;
      }
      await _format(sdk, copies.values.toList());
      return {
        for (final MapEntry(:key, :value) in copies.entries)
          key: File(value).readAsStringSync(),
      };
    } finally {
      if (scratch.existsSync()) scratch.deleteSync(recursive: true);
    }
  }

  /// Runs organize-imports and sort-members over every resolved unit and
  /// returns the files whose content they change, with the new content.
  ///
  /// [read] gives the current text of a file, which the staged overlay may
  /// not hold yet.
  Future<Map<String, _OrganizeChange>> _organize(
    ProjectAnalyzer analyzer,
    FileFilter filter, {
    required bool organize,
    required bool sortMembers,
    required String Function(String path) read,
    required Set<String> pinned,
  }) async {
    final changes = <String, _OrganizeChange>{};
    if (organize) {
      await analyzer.applyStagedChanges();
      await for (final unit in analyzer.resolvedUnits()) {
        if (filter.shouldSkip(unit.path) || pinned.contains(unit.path)) {
          continue;
        }
        final importEdits = organizeImportEdits(
          unit.content,
          unit.unit,
          unit.lineInfo,
          unit.diagnostics,
        );
        final memberEdits = sortMembers
            ? sortMemberEdits(unit.content, unit.unit, unit.lineInfo)
            : const <SourceEdit>[];
        final collector = EditCollector()
          ..addAll(importEdits)
          ..addAll(memberEdits);
        if (collector.isEmpty) continue;
        final modified = collector.apply(unit.content);
        if (modified == unit.content) continue;
        changes[unit.path] = .new(
          content: modified,
          organized: importEdits.isNotEmpty,
          sorted: memberEdits.isNotEmpty,
        );
      }
      return changes;
    }
    for (final path in _dartFiles(filter)) {
      if (pinned.contains(path)) continue;
      final content = read(path);
      final parsed = parseString(
        content: content,
        path: path,
        throwIfDiagnostics: false,
      );
      final edits = sortMemberEdits(content, parsed.unit, parsed.lineInfo);
      if (edits.isEmpty) continue;
      final modified = (EditCollector()..addAll(edits)).apply(content);
      if (modified == content) continue;
      changes[path] = .new(content: modified, organized: false, sorted: true);
    }
    return changes;
  }

  /// The project's package name from its pubspec, used to resolve its own
  /// `package:` imports, or null when it cannot be read.
  String? _packageName() {
    try {
      final yaml = loadYaml(
        File(p.join(options.path, 'pubspec.yaml')).readAsStringSync(),
      );
      final name = yaml is YamlMap ? yaml['name'] : null;
      return name is String ? name : null;
    } on Exception {
      return null;
    }
  }

  /// Builds the per-pass, files-changed map in canonical display order, merging
  /// the structural passes with the finalize steps and leaving out [reverted]
  /// files, which ended up unchanged.
  Map<String, int> _passCounts(
    Map<String, Set<String>> passesByFile,
    Map<String, int> finalizeCounts, {
    Set<String> reverted = const {},
  }) {
    final structural = <String, int>{};
    for (final MapEntry(:key, :value) in passesByFile.entries) {
      if (reverted.contains(key)) continue;
      for (final name in value) {
        structural[name] = (structural[name] ?? 0) + 1;
      }
    }
    final all = {...structural, ...finalizeCounts};
    final order = [
      for (final stage in buildTransformationStages(options))
        for (final t in stage) t.name,
      'fix-all',
      'lint-fixes',
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

  /// Rewrites the relative paths in a copied `analysis_options.yaml`'s
  /// `include:` so they still resolve from `.dart_tool/dart_modernize/`.
  String _relocateIncludes(String original) {
    final YamlNode root;
    try {
      root = loadYamlNode(original);
    } on YamlException {
      return original;
    }
    final include = root is YamlMap ? root.nodes['include'] : null;
    final scalars = switch (include) {
      YamlScalar() => [include],
      YamlList() => include.nodes.whereType<YamlScalar>().toList(),
      _ => const <YamlScalar>[],
    };
    var text = original;
    for (final scalar in scalars.reversed) {
      final value = '${scalar.value}';
      if (value.contains(':') || p.isAbsolute(value)) continue;
      text = text.replaceRange(
        scalar.span.start.offset,
        scalar.span.end.offset,
        '../../$value',
      );
    }
    return text;
  }

  String _relative(String path) => TransformResult.relative(path, options.path);

  void _reportCompletion(
    TransformResult result,
    _FinalizeResult fin,
    Set<String> reverted,
  ) {
    final changed = {
      ...result.changedFiles,
      ...fin.changedPaths,
    }.difference(reverted);
    reporter.completionSummary(
      scanned: result.filesScanned,
      changed: changed.length,
      passCounts: _passCounts(
        result.passesByFile,
        fin.counts,
        reverted: reverted,
      ),
    );
    _reportHeldBack(result);
  }

  void _reportHeldBack(TransformResult result) => reporter.heldBack({
    for (final MapEntry(:key, :value) in result.heldBack.entries)
      _relative(key): value,
  });

  void _reportSkipped(TransformResult result, ProjectAnalyzer analyzer) {
    if (result.pinned.isNotEmpty) {
      reporter.verboseLine(
        'Left ${result.pinned.length} file(s) alone: their library is pinned '
        'to a language version before $minimumSdk (// @dart = ...).',
      );
      for (final path in result.pinned) {
        reporter.verboseLine('  ${_relative(path)}');
      }
    }
    reporter.unresolvable([
      for (final path in analyzer.unresolvable.toList()..sort())
        _relative(path),
    ]);
  }

  /// Rewrites each file in [shapes] back into its original line-ending and BOM
  /// shape (or the forced [CliOptions.lineEndings] when not auto).
  ///
  /// In auto mode a plain-LF file needs no work, so it is skipped without a
  /// read. Every other file is read, re-encoded, and written back only when the
  /// bytes actually differ, so unchanged files keep their timestamp.
  void _restoreShapes(Map<String, TextShape> shapes) {
    final target = options.lineEndings;
    for (final MapEntry(:value, :key) in shapes.entries) {
      if (target == .auto && value.isPlainLf) continue;
      final path = key;
      final String current;
      try {
        current = File(path).readAsStringSync();
      } on FileSystemException {
        continue;
      }
      final restored = value.apply(current, target);
      if (restored != current) File(path).writeAsStringSync(restored);
    }
  }

  /// Shows what a real run would write, without writing anything.
  ///
  /// The finalize steps that work in memory (organize-imports, sort-members,
  /// sort-constructors-first, `dart format` on a scratch copy) run on the
  /// staged result, so the diff and the `--check` verdict cover them. `dart
  /// fix` only works on disk; its files are listed and counted instead.
  Future<void> _runPreview(
    TransformResult result,
    ProjectAnalyzer analyzer,
    List<FinalizeTransformation> passes,
    FileFilter filter,
    DartSdk sdk,
  ) async {
    final names = {for (final pass in passes) pass.name};
    final contents = Map.of(result.finalContent);
    final steps = <String, Set<String>>{
      for (final MapEntry(:key, :value) in result.passesByFile.entries)
        key: {...value},
    };
    String current(String path) =>
        contents[path] ??
        result.originalContent[path] ??
        File(path).readAsStringSync();

    if (names.contains('organize-imports') || names.contains('sort-members')) {
      final edited = await _organize(
        analyzer,
        filter,
        organize: names.contains('organize-imports'),
        sortMembers: names.contains('sort-members'),
        read: current,
        pinned: result.pinned.toSet(),
      );
      for (final MapEntry(key: path, value: change) in edited.entries) {
        contents[path] = change.content;
        final labels = steps[path] ??= <String>{};
        if (change.organized) labels.add('organize-imports');
        if (change.sorted) labels.add('sort-members');
      }
    }
    if (names.contains('sort-constructors-first')) {
      final pinned = result.pinned.toSet();
      for (final path in _dartFiles(filter)) {
        if (pinned.contains(path)) continue;
        final modified = _sortConstructorsFirst(path, current(path));
        if (modified == null) continue;
        contents[path] = modified;
        (steps[path] ??= <String>{}).add('sort-constructors-first');
      }
    }
    if (options.format) {
      final formatted = await _formatInMemory(sdk, contents);
      for (final MapEntry(:key, :value) in formatted.entries) {
        if (value == contents[key]) continue;
        contents[key] = value;
        (steps[key] ??= <String>{}).add('dart format');
      }
    }

    final changed = [
      for (final MapEntry(:key, :value) in contents.entries)
        if (value != result.originalContent[key]) key,
    ]..sort();
    final fixFiles = names.contains('fix-all')
        ? await _dartFixPreview(sdk)
        : const <String>[];

    if (options.dryRun) {
      _reportDryRun(result, changed, contents, steps);
      reporter.dartFixPreview(fixFiles);
      _reportHeldBack(result);
    } else {
      reporter.dartFixPreview(fixFiles);
      reporter.checkSummary(
        scanned: result.filesScanned,
        changed: {...changed.map(_relative), ...fixFiles}.length,
      );
    }
    if (options.check && (changed.isNotEmpty || fixFiles.isNotEmpty)) {
      throw const CheckModifiedException();
    }
  }

  void _reportDryRun(
    TransformResult result,
    List<String> changed,
    Map<String, String> contents,
    Map<String, Set<String>> steps,
  ) {
    var totalAdded = 0;
    var totalRemoved = 0;
    final passCounts = <String, int>{};

    for (final path in changed) {
      final rel = _relative(path);
      final diffText = unifiedDiff(
        'a/$rel',
        'b/$rel',
        result.originalContent[path] ?? File(path).readAsStringSync(),
        contents[path]!,
      );

      var added = 0;
      var removed = 0;
      for (final line in diffText.split('\n')) {
        if (line.startsWith('+') && !line.startsWith('+++')) added++;
        if (line.startsWith('-') && !line.startsWith('---')) removed++;
      }
      totalAdded += added;
      totalRemoved += removed;

      final passes = (steps[path] ?? const <String>{}).toList();
      reporter.renderDiff(rel, passes, added, removed, diffText);
      for (final name in passes) {
        passCounts[name] = (passCounts[name] ?? 0) + 1;
      }
    }

    reporter.dryRunSummary(
      scanned: result.filesScanned,
      changed: changed.length,
      added: totalAdded,
      removed: totalRemoved,
      passCounts: _passCounts(const {}, passCounts),
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

  /// [content] with constructors lifted first, or null when nothing moves.
  String? _sortConstructorsFirst(String path, String content) {
    final parsed = parseString(
      content: content,
      path: path,
      throwIfDiagnostics: false,
    );
    final edits = sortConstructorsFirstEdits(
      content,
      parsed.unit,
      parsed.lineInfo,
    );
    if (edits.isEmpty) return null;
    final modified = (EditCollector()..addAll(edits)).apply(content);
    return modified == content ? null : modified;
  }

  /// Raises the SDK constraint to the tool's floor, refreshes the package
  /// config, and removes the `final` and `var` modifiers Dart 3.13 rejects on
  /// ordinary parameters, so the project compiles before any pass runs.
  Future<void> _upgradeSdk(DartSdk sdk) async {
    final from = raiseSdkConstraint(options.path);
    if (from == null) {
      reporter.verboseLine(
        'The SDK constraint already starts at $minimumSdk; nothing to upgrade.',
      );
      return;
    }
    reporter.sdkUpgraded(from, '^$minimumSdk');
    await _runProcess(sdk.dartExecutable, ['pub', 'get']);
    await _runProcess(sdk.dartExecutable, [
      'fix',
      '--apply',
      '--code=extraneous_modifier',
      options.path,
    ]);
  }

  /// Splits [items] into consecutive chunks of at most [size].
  static Iterable<List<T>> _batches<T>(List<T> items, int size) sync* {
    for (var i = 0; i < items.length; i += size) {
      yield items.sublist(i, i + size > items.length ? items.length : i + size);
    }
  }

  /// Paths in [before] whose on-disk content has since changed.
  static List<String> _changedSince(Map<String, String> before) => [
    for (final MapEntry(:key, :value) in before.entries)
      if (File(key).readAsStringSync() != value) key,
  ];

  /// Rewrites any path in [snapshot] whose on-disk content no longer matches
  /// back to its snapshotted content.
  static void _restore(Map<String, String> snapshot) {
    for (final MapEntry(:key, :value) in snapshot.entries) {
      if (File(key).readAsStringSync() != value) {
        File(key).writeAsStringSync(value);
      }
    }
  }

  /// Reads the current on-disk content of each path in [files].
  static Map<String, String> _snapshot(List<String> files) => {
    for (final f in files) f: File(f).readAsStringSync(),
  };
}

/// Outcome of the finalize stage.
final class const _FinalizeResult({
  final Map<String, int> counts = const {},
  final Set<String> changedPaths = const {},
  final Map<String, Set<String>> stepsByFile = const {},
});

/// One file's organize-imports / sort-members result.
final class const _OrganizeChange({
  required final String content,
  required final bool organized,
  required final bool sorted,
});
