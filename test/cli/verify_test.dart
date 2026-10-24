/// Behavioural spec for the final check (`--verify`, on by default).
///
/// Once the files are written, `dart analyze` runs over the whole project, and
/// the changes behind every new error are undone: the broken file itself, or
/// the changed files a broken caller depends on, round after round, and the
/// rest of the run when an error cannot be traced. Real passes are not
/// supposed to break code (and the in-memory check of each stage already
/// catches what they would), so the revert logic is exercised directly, with a
/// stand-in for `dart analyze`.
library;

import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:dart_modernize/src/analysis/sdk_analysis.dart';
import 'package:dart_modernize/src/engine/import_graph.dart';
import 'package:dart_modernize/src/pipeline/project_verifier.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/analysis_helper.dart';
import '../support/cli_harness.dart';

const _error = SdkDiagnostic(
  severity: 'ERROR',
  code: 'NOT_ENOUGH_POSITIONAL_ARGUMENTS',
  message: '2 positional arguments expected',
);

/// The project files a scenario works on, by name.
typedef _Files = ({String pair, String use, String other});

/// Writes `lib/pair.dart`, its caller `lib/use.dart`, and an unrelated
/// `lib/other.dart`, and returns a verifier whose `dart analyze` answers with
/// the maps [rounds] builds, one per call (the last one repeats).
({ProjectVerifier verifier, _Files files, int Function() calls}) _scenario(
  List<Map<String, List<SdkDiagnostic>>> Function(_Files files) rounds,
) {
  final project = createProject(
    files: {
      'lib/pair.dart': 'class Pair(final int a, final int b);\n',
      'lib/use.dart': "import 'pair.dart';\n\nfinal p = Pair(1, 2);\n",
      'lib/other.dart': 'final x = 1;\n',
    },
  );
  final root = p.normalize(project.absolute.path);
  String path(String name) => p.join(root, 'lib', name);
  final files = (
    pair: path('pair.dart'),
    use: path('use.dart'),
    other: path('other.dart'),
  );
  final graph = ImportGraph(root, 'fixture_project');
  for (final file in [files.pair, files.use, files.other]) {
    graph.add(file, parseString(content: File(file).readAsStringSync()).unit);
  }
  final answers = rounds(files);
  var calls = 0;
  final verifier = ProjectVerifier(
    analyze: () async {
      final answer =
          answers[calls < answers.length ? calls : answers.length - 1];
      calls++;
      return answer;
    },
    graph: graph,
    projectPath: root,
  );
  return (verifier: verifier, files: files, calls: () => calls);
}

Map<String, List<SdkDiagnostic>> _errorIn(String path) => {
  p.canonicalize(path): [_error],
};

const _originalPair = 'class Pair {}\n';
const _originalOther = 'var x = 1;\n';

void main() {
  group('ProjectVerifier', () {
    test('keeps everything when nothing new breaks', () async {
      final s = _scenario((_) => [{}]);
      final outcome = await s.verifier.verify(
        baseline: const {},
        changed: {s.files.pair},
        originals: {s.files.pair: _originalPair},
        files: [s.files.pair, s.files.use],
      );
      expect(outcome.reverted, isEmpty);
      expect(File(s.files.pair).readAsStringSync(), contains('class Pair('));
      expect(s.calls(), 1);
    });

    test('reverts a changed file that gained an error', () async {
      final s = _scenario((f) => [_errorIn(f.pair), {}]);
      final outcome = await s.verifier.verify(
        baseline: const {},
        changed: {s.files.pair},
        originals: {s.files.pair: _originalPair},
        files: [s.files.pair, s.files.use],
      );
      expect(outcome.reverted.keys, [s.files.pair]);
      expect(File(s.files.pair).readAsStringSync(), _originalPair);
      expect(s.calls(), 2);
    });

    test('an error that was already there does not count', () async {
      final s = _scenario((f) => [_errorIn(f.pair)]);
      final outcome = await s.verifier.verify(
        baseline: _errorIn(s.files.pair),
        changed: {s.files.pair},
        originals: {s.files.pair: _originalPair},
        files: [s.files.pair],
      );
      expect(outcome.reverted, isEmpty);
    });

    test(
      'a new error in an unchanged caller reverts what it depends on',
      () async {
        final s = _scenario((f) => [_errorIn(f.use), {}]);
        final outcome = await s.verifier.verify(
          baseline: const {},
          changed: {s.files.pair, s.files.other},
          originals: {
            s.files.pair: _originalPair,
            s.files.other: _originalOther,
          },
          files: [s.files.pair, s.files.use, s.files.other],
        );
        expect(outcome.reverted.keys, [s.files.pair]);
        expect(
          outcome.reverted[s.files.pair]!.single,
          startsWith('in lib/use.dart:'),
        );
        expect(File(s.files.other).readAsStringSync(), 'final x = 1;\n');
      },
    );

    test('an error it cannot trace reverts the rest of the run', () async {
      final s = _scenario(
        (f) => [_errorIn(p.join(p.dirname(f.pair), 'elsewhere.dart')), {}],
      );
      final outcome = await s.verifier.verify(
        baseline: const {},
        changed: {s.files.pair, s.files.other},
        originals: {s.files.pair: _originalPair, s.files.other: _originalOther},
        files: [s.files.pair, s.files.use, s.files.other],
      );
      expect(
        outcome.reverted.keys,
        unorderedEquals([s.files.pair, s.files.other]),
      );
      expect(outcome.unexplained, isEmpty);
      expect(File(s.files.other).readAsStringSync(), _originalOther);
    });

    test(
      'reports an error that outlives every revert as not its own',
      () async {
        final s = _scenario(
          (f) => [_errorIn(p.join(p.dirname(f.pair), 'elsewhere.dart'))],
        );
        final outcome = await s.verifier.verify(
          baseline: const {},
          changed: {s.files.pair},
          originals: {s.files.pair: _originalPair},
          files: [s.files.pair],
        );
        expect(outcome.reverted.keys, [s.files.pair]);
        expect(outcome.unexplained.keys, ['lib/elsewhere.dart']);
      },
    );

    test('lists new warnings and infos without reverting them', () async {
      final s = _scenario(
        (f) => [
          {
            p.canonicalize(f.pair): [
              const SdkDiagnostic(
                severity: 'INFO',
                code: 'always_specify_types',
                message: 'Missing type annotation.',
              ),
            ],
          },
        ],
      );
      final outcome = await s.verifier.verify(
        baseline: const {},
        changed: {s.files.pair},
        originals: {s.files.pair: _originalPair},
        files: [s.files.pair],
      );
      expect(outcome.reverted, isEmpty);
      expect(outcome.newDiagnostics, {
        'lib/pair.dart': ['always_specify_types: Missing type annotation.'],
      });
    });
  });

  test('a valid modernization passes verification and is kept', () async {
    const clean = '''
enum Mode { fast, slow }

Mode pick() => Mode.fast;

String greet(String name) => 'Hello, ' + name + '!';
''';

    final project = createProject(files: {'lib/app.dart': clean});
    final run = await invokeCli(project, args: const ['--verify']);

    expect(run.exitCode, 0, reason: run.stderr);
    expect(run.stdout, contains('Verifying'));
    // dot-shorthands and string-interpolation both fired and were kept.
    expect(run.read('lib/app.dart'), contains('=> .fast;'));
    expect(run.read('lib/app.dart'), contains(r"'Hello, $name!'"));

    final after = await analyzeProject(project);
    expect(
      after.exitCode,
      0,
      reason: 'kept output must analyze clean:\n${after.output}',
    );
  });

  test('--no-verify skips both checks', () async {
    final run = await runCli(
      files: {
        'lib/app.dart': 'enum Mode { fast }\n\nMode pick() => Mode.fast;\n',
      },
      args: const ['--no-verify'],
    );
    expect(run.exitCode, 0, reason: run.stderr);
    expect(run.stdout, isNot(contains('Verifying')));
    expect(run.read('lib/app.dart'), contains('=> .fast;'));
  });
}
