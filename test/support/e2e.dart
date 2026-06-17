/// Runners for end-to-end suites that exercise **multiple passes at once** on
/// realistic, production-like files.
///
/// Two shapes are provided:
///
///   * [defineCombinedGoldenSuite]: exact before/after on curated files that
///     deliberately combine several transformations, plus semantic-safety and
///     idempotency checks. Use when the precise converged output matters.
///
///   * [defineRobustnessSuite]: runs every pass over already-modern files
///     (records, patterns, sealed classes, …) and asserts only that the tool
///     runs cleanly, the result still analyzes, and a second run is a no-op. No
///     byte-golden: this proves the tool never *breaks* modern code.
///
/// Both batch every case into a single throwaway project and invoke the CLI
/// twice total (once for output, once for idempotency) so the heavy subprocess
/// cost stays bounded.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'analysis_helper.dart';
import 'cli_harness.dart';
import 'golden.dart';

/// All passes except primary constructors, whose output needs an experimental,
/// newer language version than the fixture projects opt into, so it cannot be
/// re-analyzed cleanly here. Primary constructors keep their own golden suite.
const allStablePasses = <String>['--no-primary-constructors'];

/// Absolute path to `test/fixtures`, resolved from the package root.
final String _fixturesRoot = p.join(
  Directory.current.absolute.path,
  'test',
  'fixtures',
);

/// Defines a combined golden suite over `test/fixtures/[dir]/`.
///
/// Each `<case>.input.dart` / `<case>.expected` pair is dropped into one project,
/// the CLI is run with [args], and for every case the rewritten file must match
/// its expected output. The whole project must then analyze clean, and a second
/// run must change nothing.
void defineCombinedGoldenSuite({
  required String label,
  required String dir,
  List<String> args = const [],
  String pubspec = defaultPubspec,
}) {
  group(label, () {
    final cases = discoverCases(dir);

    test('has at least one case', () {
      expect(cases, isNotEmpty, reason: 'No fixtures in test/fixtures/$dir/.');
    });

    if (cases.isEmpty) return;

    late CliResult firstRun;
    late Directory project;

    setUpAll(() async {
      project = createProject(
        files: {for (final c in cases) c.projectFile: c.input},
        pubspec: pubspec,
      );
      firstRun = await invokeCli(project, args: args);
    });

    test('runs successfully', () {
      expect(firstRun.exitCode, 0, reason: firstRun.stderr);
    });

    for (final c in cases) {
      test('${c.name}: matches golden', () {
        expect(
          firstRun.read(c.projectFile),
          c.expected,
          reason:
              'combined output for "${c.name}" did not match '
              'test/fixtures/$dir/${c.name}.expected',
        );
      });
    }

    test('analyzes clean after modernization', () async {
      final outcome = await analyzeProject(project);
      expect(
        outcome.exitCode,
        0,
        reason: 'modernized project must analyze clean:\n${outcome.output}',
      );
    });

    test('is idempotent (second run changes nothing)', () async {
      final secondRun = await invokeCli(project, args: args);
      expect(secondRun.exitCode, 0, reason: secondRun.stderr);
      for (final c in cases) {
        expect(
          secondRun.read(c.projectFile),
          firstRun.read(c.projectFile),
          reason: '"${c.name}" changed on the second run; not idempotent',
        );
      }
    });
  });
}

/// Defines a robustness suite over the plain `*.dart` files in
/// `test/fixtures/[dir]/`.
///
/// Every file is modernized with [args] in one project. The suite asserts the
/// run succeeds, the project still analyzes without errors, and a second run is
/// a no-op. It deliberately does **not** pin exact output; its job is to prove
/// the tool handles modern syntax without corrupting it.
void defineRobustnessSuite({
  required String label,
  required String dir,
  List<String> args = const [],
  String pubspec = defaultPubspec,
}) {
  group(label, () {
    final files = _plainDartFiles(dir);

    test('has at least one file', () {
      expect(
        files,
        isNotEmpty,
        reason: 'No .dart files in test/fixtures/$dir/.',
      );
    });

    if (files.isEmpty) return;

    late CliResult firstRun;
    late Directory project;

    setUpAll(() async {
      project = createProject(files: files, pubspec: pubspec);
      firstRun = await invokeCli(project, args: args);
    });

    test('runs successfully', () {
      expect(firstRun.exitCode, 0, reason: firstRun.stderr);
    });

    test('still analyzes clean after modernization', () async {
      final outcome = await analyzeProject(project);
      expect(
        outcome.exitCode,
        0,
        reason:
            'modern code must still analyze after modernization:\n'
            '${outcome.output}',
      );
    });

    test('is idempotent (second run changes nothing)', () async {
      final secondRun = await invokeCli(project, args: args);
      expect(secondRun.exitCode, 0, reason: secondRun.stderr);
      for (final rel in files.keys) {
        expect(
          secondRun.read(rel),
          firstRun.read(rel),
          reason: '$rel changed on the second run; not idempotent',
        );
      }
    });
  });
}

/// Plain `*.dart` files in `test/fixtures/[dir]/` (not `.input`/`.expected`/
/// `.unchanged`/`.support`), mapped to their in-project path `lib/<name>.dart`.
Map<String, String> _plainDartFiles(String dir) {
  final directory = Directory(p.join(_fixturesRoot, dir));
  if (!directory.existsSync()) return const {};
  final files = <String, String>{};
  for (final entity in directory.listSync()) {
    if (entity is! File) continue;
    final name = p.basename(entity.path);
    if (!name.endsWith('.dart')) continue;
    if (name.endsWith('.input.dart') ||
        name.endsWith('.unchanged.dart') ||
        name.endsWith('.support.dart')) {
      continue;
    }
    files['lib/$name'] = entity.readAsStringSync();
  }
  return files;
}
