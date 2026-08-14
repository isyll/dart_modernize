/// Full-pipeline safety spec over a realistic, multi-file project.
///
/// This is the broadest behavioural check: a small but production-shaped package
/// is modernized with every compatible pass enabled at once, and the
/// result must be (a) actually transformed by every applicable structural pass,
/// (b) idempotent (a second run changes nothing), and (c) still analyze without
/// errors.
///
/// One run modernizes the whole project. Cases where several passes target the
/// same evolving construct are covered separately by `interaction_test.dart`;
/// see `doc/ORDERING.md`.
library;

import 'dart:io';

import 'package:test/test.dart';

import '../support/analysis_helper.dart';
import '../support/cli_harness.dart';

void main() {
  group('full pipeline over a realistic project', () {
    late Directory project;
    late Map<String, String> afterFirst;
    final stablePasses = onlyFeaturesArgs(_stable);

    setUpAll(() async {
      project = createProject(files: _projectFiles());
      final run1 = await invokeCli(project, args: stablePasses);
      expect(run1.exitCode, 0, reason: run1.stderr);
      afterFirst = {for (final f in _projectFiles().keys) f: run1.read(f)};
    });

    test('every implemented structural pass fires across the project', () {
      final models = afterFirst['lib/models.dart']!;
      final text = afterFirst['lib/text.dart']!;
      final build = afterFirst['lib/build.dart']!;

      // super-parameters
      expect(models, contains('Worker({required super.id});'));
      // dot-shorthands (enum value in an arrow method and a getter)
      expect(models, contains('Mode mode() => .fast;'));
      expect(models, contains('Status get status => .active;'));
      // sort-members (getter sorted before method within Worker)
      expect(
        models,
        stringContainsInOrder([
          'Status get status => .active;',
          'Mode mode() => .fast;',
        ]),
      );
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
      final run2 = await invokeCli(project, args: stablePasses);
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
  });
}

/// cascades, null-aware-spread, null-aware-elements, and expression-bodies, each
/// on its own construct.
const _build = '''
import 'dart:collection';

Queue<int> fill(int seed, int other) {
  final q = Queue<int>();
  q.add(seed);
  q.add(other);
  assert(q.length == 2);
  return q;
}

List<int> merge(List<int> base, List<int>? extra) {
  final all = [...base, if (extra != null) ...extra];
  return all.toList();
}

List<int> collect(int head, int? tail) {
  final xs = [head, if (tail != null) tail];
  return xs.toList();
}

int square(int x) {
  return x * x;
}
''';

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

/// Every pass but `collection_elements`, 21 of the 22, by fixture-folder name.
///
/// collection_elements is left out because it and cascades both target a run of
/// `add` calls, and whichever runs first wins. `flag_disables_pass_test.dart`
/// covers the two against each other instead.
///
/// primary_constructors and switch_expressions are listed but do not fire on
/// these files: `Base` is extended in the same file, `Worker` forwards to super,
/// and there is no eligible switch. They stay in so the set is complete.
///
/// sort_members and sort_constructors_first both order members, so running both
/// is what makes the idempotence check meaningful.
const _stable = <String>{
  'dot_shorthands',
  'private_named_parameters',
  'primary_constructors',
  'super_parameters',
  'switch_expressions',
  'cascades',
  'inline_return',
  'final_locals',
  'prefer_inferred_types',
  'expression_bodies',
  'string_interpolation',
  'null_aware_spread',
  'null_aware_elements',
  'null_aware_conditionals',
  'destructure_for_in',
  'destructure_locals',
  'organize_imports',
  'sort_members',
  'sort_constructors_first',
  'fix_all',
  'abstract_final_classes',
};

/// string-interpolation in an arrow body and in a multi-statement body.
const _text = '''
String greet(String name) => 'Hello, ' + name + '!';

String label(String prefix, String value) {
  final combined = prefix + ': ' + value;
  return combined.trim();
}
''';

Map<String, String> _projectFiles() => const {
  'lib/models.dart': _models,
  'lib/text.dart': _text,
  'lib/build.dart': _build,
};
