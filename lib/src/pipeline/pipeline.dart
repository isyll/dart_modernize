import 'dart:io';

import 'package:path/path.dart' as p;

import '../analysis/project_analyzer.dart';
import '../analysis/validator.dart';
import '../cli/options.dart';
import '../engine/edit_collector.dart';
import '../engine/file_filter.dart';
import 'transformation.dart';

/// Orchestrates the full modernization pipeline.
///
/// Stages: **validate** → **resolve** → **transform** → **finalize**.
final class ModernizePipeline {
  const ModernizePipeline({
    required this.options,
    required this.transformations,
  });

  final CliOptions options;
  final List<Transformation> transformations;

  Future<void> run() async {
    // 1. Validate: fast-fail before touching the analyzer.
    await validateProject(options.path);
    stdout.writeln('✓ Project validated.');

    // 2. Filter to only enabled transformations.
    final active = transformations.where((t) => t.enabled).toList();
    if (active.isEmpty) {
      stdout.writeln('No transformations enabled; nothing to do.');
      return;
    }

    // 3. Resolve and transform, file by file.
    final analyzer = ProjectAnalyzer(options.path);
    analyzer.initialize();

    var filesChanged = 0;
    await for (final unit in analyzer.resolvedUnits()) {
      if (isGeneratedFile(unit.path)) continue;

      final collector = EditCollector();
      for (final transform in active) {
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

    // 4. Finalize: only when files were actually written.
    if (filesChanged > 0) {
      await _finalize();
    }
  }

  Future<void> _finalize() async {
    stdout.writeln('Finalizing…');
    // TODO: organize-imports pass (dart:analysis rewrite)
    // TODO: sort-members pass
    // TODO: dart fix --apply
    // TODO: dart format .
    // TODO: re-analyze and confirm zero new errors
  }

  void _printDiff(String filePath, String original, String modified) {
    final rel = p.relative(filePath, from: options.path);
    stdout.writeln('--- a/$rel');
    stdout.writeln('+++ b/$rel');
    // TODO: unified diff output
    final origLines = original.split('\n').length;
    final modLines = modified.split('\n').length;
    stdout.writeln('@@ $origLines → $modLines lines @@');
    stdout.writeln();
  }
}
