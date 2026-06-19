/// Full-pipeline safety spec over a realistic, multi-file project.
///
/// This is the broadest behavioural check: a small but production-shaped package
/// is modernized with **all seven implemented passes** enabled at once, and the
/// result must be (a) actually transformed by every pass, (b) idempotent — a
/// second run changes nothing — and (c) still analyze without errors. A final
/// case proves the six stub passes are inert: enabling them on top changes
/// nothing.
///
/// The fixture deliberately keeps each transformable construct owned by a single
/// pass (no two passes target the same span), so the project converges in one
/// run. Same-construct overlaps, which converge only across runs, are covered
/// separately by `interaction_test.dart`; see `doc/ORDERING.md`.
library;

import 'dart:io';

import 'package:test/test.dart';

import '../support/analysis_helper.dart';
import '../support/cli_harness.dart';

/// The seven passes with real visitor logic (fixture-folder names).
const _implemented = <String>{
  'dot_shorthands',
  'super_parameters',
  'cascades',
  'expression_bodies',
  'string_interpolation',
  'null_aware_spread',
  'null_aware_elements',
};

/// super-parameters (full forward) + dot-shorthands (already-arrow methods).
const _models = '''
enum Mode { fast, slow }

enum Status { active, idle }

class Base {
  final int id;

  Base({required this.id});
}

class Worker extends Base {
  Worker({required int id}) : super(id: id);

  Mode mode() => Mode.fast;

  Status get status => Status.active;
}
''';

/// string-interpolation in an arrow body and in a multi-statement body.
const _text = '''
String greet(String name) => 'Hello, ' + name + '!';

String label(String prefix, String value) {
  final combined = prefix + ': ' + value;
  return combined;
}
''';

/// cascades, null-aware-spread, null-aware-elements, and expression-bodies, each
/// on its own construct.
const _build = '''
import 'dart:collection';

Queue<int> fill(int seed, int other) {
  final q = Queue<int>();
  q.add(seed);
  q.add(other);
  return q;
}

List<int> merge(List<int> base, List<int>? extra) {
  final all = [...base, if (extra != null) ...extra];
  return all;
}

List<int> collect(int head, int? tail) {
  final xs = [head, if (tail != null) tail];
  return xs;
}

int square(int x) {
  return x * x;
}
''';

Map<String, String> _projectFiles() => const {
  'lib/models.dart': _models,
  'lib/text.dart': _text,
  'lib/build.dart': _build,
};

void main() {
  group('full pipeline over a realistic project', () {
    late Directory project;
    late Map<String, String> afterFirst;
    final sevenPasses = onlyFeaturesArgs(_implemented);

    setUpAll(() async {
      project = createProject(files: _projectFiles());
      final run1 = await invokeCli(project, args: sevenPasses);
      expect(run1.exitCode, 0, reason: run1.stderr);
      afterFirst = {for (final f in _projectFiles().keys) f: run1.read(f)};
    });

    test('every implemented pass fires across the project', () {
      final models = afterFirst['lib/models.dart']!;
      final text = afterFirst['lib/text.dart']!;
      final build = afterFirst['lib/build.dart']!;

      // super-parameters
      expect(models, contains('Worker({required super.id});'));
      // dot-shorthands (enum value in an arrow method and a getter)
      expect(models, contains('Mode mode() => .fast;'));
      expect(models, contains('Status get status => .active;'));
      // string-interpolation (arrow body and multi-statement body)
      expect(text, contains("String greet(String name) => 'Hello, \$name!';"));
      expect(text, contains("final combined = '\$prefix: \$value';"));
      // cascades
      expect(
        build,
        contains('final q = Queue<int>()\n    ..add(seed)\n    ..add(other);'),
      );
      // null-aware-spread
      expect(build, contains('[...base, ...?extra]'));
      // null-aware-elements
      expect(build, contains('[head, ?tail]'));
      // expression-bodies
      expect(build, contains('int square(int x) => x * x;'));
    });

    test('a second run changes nothing (idempotent)', () async {
      final run2 = await invokeCli(project, args: sevenPasses);
      expect(run2.exitCode, 0, reason: run2.stderr);
      for (final f in _projectFiles().keys) {
        expect(
          run2.read(f),
          afterFirst[f],
          reason:
              '$f changed on the second run; the pipeline is not idempotent',
        );
      }
    });

    test('the modernized project still analyzes without errors', () async {
      final outcome = await analyzeProject(project);
      expect(
        outcome.exitCode,
        0,
        reason: 'modernized project must analyze clean:\n${outcome.output}',
      );
    });

    test(
      'the six stub passes are inert: enabling them changes nothing',
      () async {
        // Default args = all thirteen passes on. The six stubs return no edits, so
        // the output must be byte-identical to the seven-implemented-only run.
        final withStubs = createProject(files: _projectFiles());
        final run = await invokeCli(withStubs);
        expect(run.exitCode, 0, reason: run.stderr);
        for (final f in _projectFiles().keys) {
          expect(
            run.read(f),
            afterFirst[f],
            reason: 'enabling the stub passes altered $f; stubs must be inert',
          );
        }
      },
    );
  });
}
