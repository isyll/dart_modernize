import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:analyzer/dart/analysis/utilities.dart';

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

/// Orchestrates the full modernization pipeline.
///
/// Stages: **validate** -> **resolve** -> **transform** -> **finalize**.
///
/// The finalize order is fixed:
///   1. `dart fix --apply`   : fixes may remove imports, so it runs first.
///   2. organize-imports     : sorts/prunes after fixes have settled.
///   3. sort-members         : reorders class members after imports are clean.
///   4. `dart format`        : always last so previous edits are formatted.
final class ModernizePipeline {
  final CliOptions options;
  final Reporter reporter;
  final List<Transformation> transformations;

  const ModernizePipeline({
    required this.options,
    required this.reporter,
    required this.transformations,
  });

  Future<void> run() async {
    // 1. Validate: fast-fail before touching the analyzer.
    await validateProject(options.path);
    reporter.validated();

    // Separate structural passes (AST visitors) from finalize passes.
    final enabled = transformations.where((t) => t.enabled).toList();
    if (enabled.isEmpty) {
      reporter.nothingToDo();
      return;
    }
    final structural = enabled
        .where((t) => t is! FinalizeTransformation)
        .toList();
    final finalize = enabled.whereType<FinalizeTransformation>().toList();

    // 2. Resolve and transform, file by file (structural passes only).
    reporter.resolving();
    final filter = FileFilter.forProject(
      options.path,
      cliExcludes: options.excludes,
    );
    final analyzer = ProjectAnalyzer(options.path)..initialize();

    var filesScanned = 0;
    var filesChanged = 0;
    var totalAdded = 0;
    var totalRemoved = 0;
    final passFileCounts = <String, int>{};

    await for (final unit in analyzer.resolvedUnits()) {
      if (filter.shouldSkip(unit.path)) continue;
      filesScanned++;

      final collector = EditCollector();
      final passesWithEdits = <String>[];
      for (final transform in structural) {
        final edits = await transform.editsFor(unit);
        if (edits.isNotEmpty) {
          passesWithEdits.add(transform.name);
          passFileCounts[transform.name] =
              (passFileCounts[transform.name] ?? 0) + 1;
        }
        collector.addAll(edits);
      }
      if (collector.isEmpty) continue;

      final original = unit.content;
      final modified = collector.apply(original);
      filesChanged++;

      if (options.dryRun) {
        final rel = p
            .relative(unit.path, from: options.path)
            .replaceAll(r'\', '/');
        final diffText = unifiedDiff('a/$rel', 'b/$rel', original, modified);

        var fileAdded = 0;
        var fileRemoved = 0;
        for (final line in diffText.split('\n')) {
          if (line.startsWith('+') && !line.startsWith('+++')) fileAdded++;
          if (line.startsWith('-') && !line.startsWith('---')) fileRemoved++;
        }
        totalAdded += fileAdded;
        totalRemoved += fileRemoved;

        reporter.renderDiff(
          rel,
          passesWithEdits,
          fileAdded,
          fileRemoved,
          diffText,
        );
      } else {
        File(unit.path).writeAsStringSync(modified);
      }
    }

    if (options.dryRun) {
      reporter.dryRunSummary(
        scanned: filesScanned,
        changed: filesChanged,
        added: totalAdded,
        removed: totalRemoved,
        passCounts: passFileCounts,
      );
      return;
    }

    reporter.liveSummary(filesChanged);

    // 3. Finalize: run when structural changes happened OR finalize passes are
    //    enabled (they can fire even if no structural edits were made).
    if (filesChanged > 0 || finalize.isNotEmpty) {
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

    // Organize-imports and sort-members, both in-process via the analyzer.
    //
    // Organize-imports needs a resolved unit (unused/duplicate-import
    // diagnostics drive pruning), which requires a resolved package config, so
    // pub get must run first. Sort-members is purely syntactic, so when it runs
    // alone the files are only parsed, with no resolution or pub get.
    //
    // The two passes edit disjoint regions (directives vs declarations), so
    // their edits are computed on the same source and merged.
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
    // formatted. Exit 65 means the formatter encountered a parse error (e.g.
    // the project uses syntax newer than the locally-installed SDK). The
    // transformation has already been written to disk, so treat this as a
    // non-fatal warning rather than aborting the pipeline.
    reporter.finalizingStep('dart format');
    await _runProcess(
      Platform.resolvedExecutable,
      ['format', projectPath],
      allowedExitCodes: {65},
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
}
