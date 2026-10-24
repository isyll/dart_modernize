/// Spec for the in-memory check after each stage: a stage that introduces an
/// error has the edits behind it taken back before anything is written, even
/// when the error lands in a file the stage did not touch.
///
/// Real passes are not supposed to break code, so these use stand-in passes
/// that do it on purpose.
library;

import 'dart:io';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:dart_modernize/dart_modernize.dart';
import 'package:dart_modernize/src/analysis/project_analyzer.dart';
import 'package:dart_modernize/src/engine/file_filter.dart';
import 'package:dart_modernize/src/engine/import_graph.dart';
import 'package:dart_modernize/src/output/reporter.dart';
import 'package:dart_modernize/src/pipeline/stage_runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/cli_harness.dart';

/// Renames `class Pair` to `class Couple`, which breaks every caller.
final class _RenamePair implements Transformation {
  const _RenamePair();

  @override
  bool get enabled => true;

  @override
  String get name => 'rename-pair';

  @override
  Future<List<SourceEdit>> editsFor(ResolvedUnitResult unit) async {
    final offset = unit.content.indexOf('class Pair');
    if (offset < 0) return const [];
    return [.new(offset: offset + 6, length: 4, replacement: 'Couple')];
  }
}

/// Adds a harmless comment at the end of every file that declares a class.
final class _Annotate implements Transformation {
  const _Annotate();

  @override
  bool get enabled => true;

  @override
  String get name => 'annotate';

  @override
  Future<List<SourceEdit>> editsFor(ResolvedUnitResult unit) async {
    if (!unit.content.contains('class ')) return const [];
    return [
      .new(offset: unit.content.length, length: 0, replacement: '// seen\n'),
    ];
  }
}

Future<TransformResult> _run(
  Directory project,
  List<List<Transformation>> stages, {
  required bool check,
}) {
  final analyzer = ProjectAnalyzer(p.normalize(project.absolute.path))
    ..initialize();
  return StageRunner(
    analyzer: analyzer,
    filter: FileFilter.forProject(project.path),
    graph: ImportGraph(p.normalize(project.absolute.path), 'fixture_project'),
    reporter: Reporter(color: false, verbose: false, out: StringBuffer()),
    checkEachStage: check,
  ).run(stages);
}

void main() {
  const pair = 'class Pair {\n  const Pair();\n}\n';
  const caller = "import 'pair.dart';\n\nconst p = Pair();\n";

  test('without the check, the breaking edit goes through', () async {
    final project = createProject(
      files: {'lib/pair.dart': pair, 'lib/caller.dart': caller},
    );
    final result = await _run(project, [
      [const _RenamePair()],
    ], check: false);
    expect(result.changedFiles.map(p.basename), ['pair.dart']);
  });

  test(
    'a stage that breaks a caller is taken back, other passes kept',
    () async {
      final project = createProject(
        files: {'lib/pair.dart': pair, 'lib/caller.dart': caller},
      );
      final result = await _run(project, [
        [const _RenamePair(), const _Annotate()],
      ], check: true);

      final pairPath = result.originalContent.keys.firstWhere(
        (path) => p.basename(path) == 'pair.dart',
      );
      expect(result.heldBack[pairPath], {'rename-pair'});
      expect(result.finalContent[pairPath], '$pair// seen\n');
      expect(result.passesByFile[pairPath], {'annotate'});
    },
  );

  test('the check leaves a clean stage alone', () async {
    final project = createProject(
      files: {'lib/pair.dart': pair, 'lib/caller.dart': caller},
    );
    final result = await _run(project, [
      [const _Annotate()],
    ], check: true);
    expect(result.heldBack, isEmpty);
    expect(result.changedFiles, hasLength(1));
  });
}
