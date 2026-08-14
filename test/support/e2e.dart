/// Runners for end-to-end suites that exercise **multiple passes at once** on
/// realistic, production-like files.
///
/// Two shapes are provided:
///
///   * [defineCombinedGoldenSuite]: exact before/after on curated files that
///     combine several transformations, plus analyze-clean, idempotency and
///     determinism checks. Use when the exact output matters.
///
///   * [defineRobustnessSuite]: runs every pass over already-modern files
///     (records, patterns, sealed classes, …) and asserts only that the tool
///     runs cleanly, the result still analyzes, and a second run is a no-op. No
///     byte-golden: this proves the tool never *breaks* modern code.
///
/// Both batch every case into a single throwaway project to keep the subprocess
/// cost down.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'analysis_helper.dart';
import 'cli_harness.dart';
import 'golden.dart';

/// Every pass except primary constructors, for the suites that pin exact bytes.
///
/// Promoting a class rewrites its whole declaration, which would churn every
/// combined golden and hide the pass interactions those files are there to
/// show. sort-members is switched on because the goldens expect sorted members.
const allStablePasses = <String>['--no-primary-constructors', '--sort-members'];

/// Every pass, primary constructors included. For suites that pin no bytes.
const everyPass = <String>['--sort-members'];

/// Absolute path to `test/fixtures`, resolved from the package root.
final String _fixturesRoot = p.join(
  Directory.current.absolute.path,
  'test',
  'fixtures',
);

/// Defines a combined golden suite over `test/fixtures/[dir]/`.
///
/// Each `<case>.input.dart` / `<case>.expected.dart` pair goes into one project,
/// the CLI runs with [args], and every rewritten file must match its expected
/// output. The project must then analyze clean, and a second run change nothing.
void defineCombinedGoldenSuite({
  required String label,
  required String dir,
  List<String> args = const [],
  String pubspec = defaultPubspec,
}) {
  group(label, () {
    final cases = discoverCases(dir);

    test(
      'has at least one case',
      () => expect(
        cases,
        isNotEmpty,
        reason: 'No fixtures in test/fixtures/$dir/.',
      ),
    );

    if (cases.isEmpty) return;

    late CliResult firstRun;
    late Directory project;

    setUpAll(() async {
      project = createProject(
        files: {
          for (final GoldenCase(:projectFile, :input) in cases)
            projectFile: input,
        },
        pubspec: pubspec,
      );
      firstRun = await invokeCli(project, args: args);
    });

    test(
      'runs successfully',
      () => expect(firstRun.exitCode, 0, reason: firstRun.stderr),
    );

    for (final c in cases) {
      test(
        '${c.name}: matches golden',
        () => expect(
          firstRun.read(c.projectFile),
          c.expected,
          reason:
              'combined output for "${c.name}" did not match '
              'test/fixtures/$dir/${c.name}.expected.dart',
        ),
      );
    }

    test('analyzes clean after modernization', () async {
      final outcome = await analyzeProject(project);
      expect(
        outcome.exitCode,
        0,
        reason: 'modernized project must analyze clean:\n${outcome.output}',
      );
    });

    test('is idempotent (further runs change nothing)', () async {
      // Once modernized, the project must stay put however many times the tool
      // is re-applied.
      for (var pass = 2; pass <= 3; pass++) {
        final rerun = await invokeCli(project, args: args);
        expect(rerun.exitCode, 0, reason: rerun.stderr);
        for (final GoldenCase(:projectFile, :name) in cases) {
          expect(
            rerun.read(projectFile),
            firstRun.read(projectFile),
            reason: '"$name" changed on run #$pass; not idempotent',
          );
        }
      }
    });

    test('output is deterministic across independent runs', () async {
      // A fresh project with byte-identical inputs must produce byte-identical
      // outputs: the result cannot depend on hidden ordering or state.
      final fresh = createProject(
        files: {for (final c in cases) c.projectFile: c.input},
        pubspec: pubspec,
      );
      final freshRun = await invokeCli(fresh, args: args);
      expect(freshRun.exitCode, 0, reason: freshRun.stderr);
      for (final c in cases) {
        expect(
          freshRun.read(c.projectFile),
          firstRun.read(c.projectFile),
          reason:
              '"${c.name}" differs between two independent runs; output is '
              'not deterministic',
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
/// a no-op. It does not pin exact output; the point is that modern syntax
/// survives the tool intact.
void defineRobustnessSuite({
  required String label,
  required String dir,
  List<String> args = const [],
  String pubspec = defaultPubspec,
}) {
  group(label, () {
    final files = _plainDartFiles(dir);

    test(
      'has at least one file',
      () => expect(
        files,
        isNotEmpty,
        reason: 'No .dart files in test/fixtures/$dir/.',
      ),
    );

    if (files.isEmpty) return;

    late CliResult firstRun;
    late Directory project;

    setUpAll(() async {
      project = createProject(files: files, pubspec: pubspec);
      firstRun = await invokeCli(project, args: args);
    });

    test(
      'runs successfully',
      () => expect(firstRun.exitCode, 0, reason: firstRun.stderr),
    );

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
        name.endsWith('.expected.dart') ||
        name.endsWith('.unchanged.dart') ||
        name.endsWith('.support.dart')) {
      continue;
    }
    files['lib/$name'] = entity.readAsStringSync();
  }
  return files;
}
