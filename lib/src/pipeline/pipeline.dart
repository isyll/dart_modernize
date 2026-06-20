import 'dart:io';

import 'package:path/path.dart' as p;

import '../analysis/project_analyzer.dart';
import '../analysis/validator.dart';
import '../cli/options.dart';
import '../engine/analysis_server.dart';
import '../engine/edit_collector.dart';
import '../engine/file_filter.dart';
import '../engine/source_edit.dart';
import '../engine/unified_diff.dart';
import '../modernize_exception.dart';
import 'transformation.dart';

/// Orchestrates the full modernization pipeline.
///
/// Stages: **validate** → **resolve** → **transform** → **finalize**.
///
/// The finalize order is fixed:
///   1. `dart fix --apply`   : fixes may remove imports, so it runs first.
///   2. organize-imports     : sorts/prunes after fixes have settled.
///   3. sort-members         : reorders class members after imports are clean.
///   4. `dart format`        : always last so previous edits are formatted.
final class ModernizePipeline {
  final CliOptions options;

  final List<Transformation> transformations;
  const ModernizePipeline({
    required this.options,
    required this.transformations,
  });

  Future<void> run() async {
    // 1. Validate: fast-fail before touching the analyzer.
    await validateProject(options.path);
    stdout.writeln('✓ Project validated.');

    // Separate structural passes (AST visitors) from finalize passes.
    final enabled = transformations.where((t) => t.enabled).toList();
    if (enabled.isEmpty) {
      stdout.writeln('No transformations enabled; nothing to do.');
      return;
    }
    final structural = enabled
        .where((t) => t is! FinalizeTransformation)
        .toList();
    final finalize = enabled.whereType<FinalizeTransformation>().toList();

    // 2. Resolve and transform, file by file (structural passes only).
    final analyzer = ProjectAnalyzer(options.path)..initialize();

    var filesChanged = 0;
    await for (final unit in analyzer.resolvedUnits()) {
      if (isGeneratedFile(unit.path)) continue;

      final collector = EditCollector();
      for (final transform in structural) {
        collector.addAll(await transform.editsFor(unit));
      }
      if (collector.isEmpty) continue;

      final original = unit.content;
      final modified = collector.apply(original);
      filesChanged++;

      if (options.dryRun) {
        _printDiff(unit.path, original, modified);
      } else {
        File(unit.path).writeAsStringSync(modified);
      }
    }

    if (options.dryRun) {
      stdout.writeln(
        '$filesChanged file(s) would change (dry run, nothing written).',
      );
      return;
    }

    stdout.writeln('$filesChanged file(s) changed.');

    // 3. Finalize: run when structural changes happened OR finalize passes are
    //    enabled (they can fire even if no structural edits were made).
    if (filesChanged > 0 || finalize.isNotEmpty) {
      await _finalize(finalize);
    }
  }

  /// Returns every non-generated `.dart` file under [projectPath].
  List<String> _dartFiles(String projectPath) {
    return Directory(projectPath)
        .listSync(recursive: true)
        .whereType<File>()
        .map((f) => f.path)
        .where((fp) => fp.endsWith('.dart') && !isGeneratedFile(fp))
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

  Future<void> _finalize(List<FinalizeTransformation> passes) async {
    stdout.writeln('Finalizing…');

    final projectPath = options.path;
    final hasFixAll = passes.any((p) => p.name == 'fix-all');
    final hasOrganize = passes.any((p) => p.name == 'organize-imports');
    final hasSortMembers = passes.any((p) => p.name == 'sort-members');

    // Fix-all: dart fix --apply.
    // Runs before import organization so that fixes that remove imports are
    // reflected before organize-imports decides what to prune.
    if (hasFixAll) {
      stdout.writeln('  dart fix --apply…');
      await _ensurePubGet(projectPath);
      await _runProcess(Platform.resolvedExecutable, [
        'fix',
        '--apply',
        projectPath,
      ]);
    }

    // Organize-imports and sort-members via the analysis server.
    // Both need a live server; start once, process all files, then stop.
    // pub get must have been run before the server starts so it can resolve
    // package config and dart: imports correctly.
    if (hasOrganize || hasSortMembers) {
      await _ensurePubGet(projectPath);
      stdout.writeln(
        '  ${[if (hasOrganize) 'organize-imports', if (hasSortMembers) 'sort-members'].join(' + ')} via analysis server…',
      );
      // Phase 1: query every file while files are unchanged on disk.
      // Writing files during query causes CONTENT_MODIFIED errors on
      // subsequent requests because the server detects the disk changes
      // and re-analyzes.  Collect all edits first, stop the server, then
      // apply in phase 2.
      final pendingEdits = <String, List<SourceEdit>>{};
      final server = await AnalysisServerWrapper.start(projectPath);
      try {
        for (final filePath in _dartFiles(projectPath)) {
          final edits = <SourceEdit>[];
          if (hasOrganize) {
            edits.addAll(await server.organizeDirectives(filePath));
          }
          if (hasSortMembers) {
            edits.addAll(await server.sortMembers(filePath));
          }
          if (edits.isNotEmpty) pendingEdits[filePath] = edits;
        }
      } finally {
        await server.stop();
      }
      // Phase 2: apply edits after the server is stopped.
      for (final entry in pendingEdits.entries) {
        final original = File(entry.key).readAsStringSync();
        final modified = (EditCollector()..addAll(entry.value)).apply(original);
        if (modified != original) File(entry.key).writeAsStringSync(modified);
      }
    }

    // dart format: always last so all previous edits end up consistently
    // formatted.
    stdout.writeln('  dart format…');
    await _runProcess(Platform.resolvedExecutable, ['format', projectPath]);
  }

  void _printDiff(String filePath, String original, String modified) {
    final rel = p.relative(filePath, from: options.path).replaceAll(r'\', '/');
    stdout.write(unifiedDiff('a/$rel', 'b/$rel', original, modified));
    stdout.writeln();
  }

  Future<void> _runProcess(
    String executable,
    List<String> args, {
    String? workingDirectory,
  }) async {
    final result = await Process.run(
      executable,
      args,
      workingDirectory: workingDirectory ?? options.path,
    );
    if (result.exitCode != 0) {
      throw ModernizeException(
        '$executable ${args.join(' ')} failed (exit ${result.exitCode}).\n'
        '${result.stderr}',
      );
    }
  }
}
