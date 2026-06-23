/// Cross-feature interaction spec for the **implemented** passes.
///
/// The golden suites exercise one pass at a time. This suite covers what they
/// cannot: what happens when several passes apply to the *same file*, and
/// especially the *same construct*, in a single run. The pipeline resolves each
/// file once and runs every enabled pass against that one AST, then merges their
/// edits (see [ModernizePipeline] and `EditCollector`). Two regimes fall out of
/// that design, and each gets its own group below.
///
///   * **Compose cleanly**: passes that touch *disjoint* regions all apply in a
///     single run and the result is byte-stable on re-run. Output is also
///     *subset-invariant*: enabling the full implemented set produces the same
///     bytes as enabling only the passes that own those constructs, because the
///     others have nothing to do.
///
///   * **Converge across runs**: when two passes target *overlapping* spans of
///     one construct, `EditCollector` keeps the earlier-offset edit and drops
///     the other (it never corrupts offsets). The dropped edit simply applies on
///     the *next* run, so the tool converges to the fully-modernized form but is
///     not single-run idempotent for those constructs. This is the documented
///     consequence of running every pass on a single resolution with no
///     re-resolution between passes; see `doc/ORDERING.md`.
///
/// Only the seven implemented passes are used here; the six stubs are inert and
/// would only mask which pass produced an edit.
library;

import 'dart:io';

import 'package:test/test.dart';

import '../support/cli_harness.dart';

void main() {
  group('compose cleanly (disjoint edits, single-run stable)', () {
    test('super-parameters folds a constructor while dot-shorthands '
        'collapses a sibling method', () async {
      const input = '''
enum Mode { fast, slow }

class Base {
  final int id;
  Base({required this.id});
}

class Derived extends Base {
  Derived({required int id}) : super(id: id);

  Mode pick() => Mode.fast;
}
''';
      const expected = '''
enum Mode { fast, slow }

class Base {
  final int id;
  Base({required this.id});
}

class Derived extends Base {
  Derived({required super.id});

  Mode pick() => .fast;
}
''';

      final project = createProject(files: {_file: input});
      final subset = onlyFeaturesArgs({'super_parameters', 'dot_shorthands'});

      expect(await _runOnce(project, subset), expected);
      // Already converged: a second run is a no-op.
      expect(await _runOnce(project, subset), expected);

      // Subset-invariant: the full implemented set yields the identical bytes,
      // because the other five passes have nothing to touch here.
      final whole = createProject(files: {_file: input});
      expect(await _runOnce(whole, onlyFeaturesArgs(_implemented)), expected);

      // Each pass owns exactly its own construct.
      final dotOnly = createProject(files: {_file: input});
      final afterDot = await _runOnce(
        dotOnly,
        onlyFeaturesArgs({'dot_shorthands'}),
      );
      expect(afterDot, contains('Mode pick() => .fast;'));
      expect(afterDot, contains('Derived({required int id}) : super(id: id);'));

      final superOnly = createProject(files: {_file: input});
      final afterSuper = await _runOnce(
        superOnly,
        onlyFeaturesArgs({'super_parameters'}),
      );
      expect(afterSuper, contains('Derived({required super.id});'));
      expect(afterSuper, contains('Mode pick() => Mode.fast;'));
    });

    test('cascades folds a write run; expression-bodies leaves the '
        'multi-statement method alone', () async {
      const input = '''
class Box {
  int w = 0;
  int h = 0;
}

Box make() {
  var b = Box();
  b.w = 1;
  b.h = 2;
  return b;
}
''';
      const expected = '''
class Box {
  int w = 0;
  int h = 0;
}

Box make() {
  var b = Box()
    ..w = 1
    ..h = 2;
  return b;
}
''';

      final project = createProject(files: {_file: input});
      final subset = onlyFeaturesArgs({'cascades', 'expression_bodies'});

      expect(await _runOnce(project, subset), expected);
      expect(await _runOnce(project, subset), expected);

      final whole = createProject(files: {_file: input});
      expect(await _runOnce(whole, onlyFeaturesArgs(_implemented)), expected);

      // expression-bodies must not fire: make() has four statements, then two
      // after the cascade fold, never a single-statement body.
      final exprOnly = createProject(files: {_file: input});
      expect(
        await _runOnce(exprOnly, onlyFeaturesArgs({'expression_bodies'})),
        input,
      );
    });

    test('null-aware-spread, string-interpolation and dot-shorthands all '
        'apply to one file in a single run', () async {
      const input = '''
enum Flag { on, off }

String describe(String label, List<int>? extra) {
  final parts = [1, if (extra != null) ...extra];
  final joined = parts.length.toString();
  return 'count: ' + label + joined;
}

Flag current() => Flag.on;
''';
      const expected = '''
enum Flag { on, off }

String describe(String label, List<int>? extra) {
  final parts = [1, ...?extra];
  final joined = parts.length.toString();
  return 'count: \$label\$joined';
}

Flag current() => .on;
''';

      final project = createProject(files: {_file: input});
      final subset = onlyFeaturesArgs({
        'null_aware_spread',
        'string_interpolation',
        'dot_shorthands',
      });

      expect(await _runOnce(project, subset), expected);
      expect(await _runOnce(project, subset), expected);

      final whole = createProject(files: {_file: input});
      expect(await _runOnce(whole, onlyFeaturesArgs(_implemented)), expected);
    });
  });

  group('converge across runs (same-construct overlap, single resolution)', () {
    // Each case has two passes that target overlapping spans of one construct.
    // The first run applies one and defers the other (its edit is dropped by
    // EditCollector, never mis-applied); the second run finishes the job. The
    // tool converges to the correct, fully-modernized form, and is then stable.
    // These are NOT single-run idempotent: the cost of one shared resolution.
    // See doc/ORDERING.md. When/if the pipeline re-resolves between passes,
    // these will converge in a single run; update the explicit run-1 assertion
    // below accordingly.

    test('expression-bodies + dot-shorthands converge on a block-return of an '
        'enum value', () async {
      const input = '''
enum Color { red, blue }

Color pick() {
  return Color.red;
}
''';
      const converged = '''
enum Color { red, blue }

Color pick() => .red;
''';
      final subset = onlyFeaturesArgs({'expression_bodies', 'dot_shorthands'});

      // Documents the limitation: one run collapses the body but defers the
      // dot-shorthand (expression-bodies re-emits the returned expression, whose
      // span hides the dot edit). If this starts passing, the pipeline has
      // gained single-run convergence; see the group comment.
      final project = createProject(files: {_file: input});
      final afterOne = await _runOnce(project, subset);
      expect(
        afterOne,
        'enum Color { red, blue }\n\nColor pick() => Color.red;\n',
        reason: 'single run defers the dot-shorthand to a second pass',
      );

      final stable = createProject(files: {_file: input});
      expect(await _runUntilStable(stable, args: subset), converged);
    });

    test('expression-bodies + string-interpolation converge on a block-return '
        'concatenation', () async {
      const input = '''
String greet(String name) {
  return 'Hello, ' + name + '!';
}
''';
      const converged = '''
String greet(String name) => 'Hello, \$name!';
''';
      final subset = onlyFeaturesArgs({
        'expression_bodies',
        'string_interpolation',
      });

      final project = createProject(files: {_file: input});
      expect(await _runUntilStable(project, args: subset), converged);
    });

    test('super-parameters + dot-shorthands converge on a partially-forwarded '
        'super call', () async {
      const input = '''
enum Level { low, high }

class Base {
  final Level level;
  final int weight;
  Base({required this.level, required this.weight});
}

class Derived extends Base {
  Derived({required int weight}) : super(level: Level.low, weight: weight);
}
''';
      const converged = '''
enum Level { low, high }

class Base {
  final Level level;
  final int weight;
  Base({required this.level, required this.weight});
}

class Derived extends Base {
  Derived({required super.weight}) : super(level: .low);
}
''';
      final subset = onlyFeaturesArgs({'super_parameters', 'dot_shorthands'});

      final project = createProject(files: {_file: input});
      expect(await _runUntilStable(project, args: subset), converged);
    });

    test('cascades + dot-shorthands converge when the dot lives in a folded '
        'cascade argument', () async {
      const input = '''
enum Color { red, blue }

class Palette {
  void add(Color c) {}
  int size = 0;
}

Palette build() {
  var p = Palette();
  p.add(Color.red);
  p.size = 1;
  return p;
}
''';
      const converged = '''
enum Color { red, blue }

class Palette {
  void add(Color c) {}
  int size = 0;
}

Palette build() {
  var p = Palette()
    ..add(.red)
    ..size = 1;
  return p;
}
''';
      final subset = onlyFeaturesArgs({'cascades', 'dot_shorthands'});

      final project = createProject(files: {_file: input});
      expect(await _runUntilStable(project, args: subset), converged);
    });
  });
}

const _file = 'lib/c.dart';

/// The implemented passes with real visitor logic (fixture-folder names).
const _implemented = <String>{
  'dot_shorthands',
  'super_parameters',
  'cascades',
  'inline_return',
  'expression_bodies',
  'string_interpolation',
  'null_aware_spread',
  'null_aware_elements',
};

/// Single run, returning the rewritten file. Asserts a zero exit.
Future<String> _runOnce(Directory project, List<String> args) async {
  final result = await invokeCli(project, args: args);
  expect(result.exitCode, 0, reason: result.stderr);
  return result.read(_file);
}

/// Runs the CLI on [project] repeatedly until a run changes nothing, then
/// returns that stable content. Fails if no fixpoint is reached within
/// [maxRuns]. Each run must exit zero.
Future<String> _runUntilStable(
  Directory project, {
  required List<String> args,
  int maxRuns = 6,
}) async {
  String? last;
  for (var i = 0; i < maxRuns; i++) {
    final result = await invokeCli(project, args: args);
    expect(result.exitCode, 0, reason: result.stderr);
    final current = result.read(_file);
    if (current == last) return current;
    last = current;
  }
  fail('no fixpoint within $maxRuns runs; last output:\n$last');
}
