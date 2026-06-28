/// Cross-feature interaction spec.
///
/// The golden suites exercise one pass at a time. This suite covers what happens
/// when several passes apply to the same file, and often the same construct, in
/// a single run.
///
/// The transform stage is a fixed sequence of dependency-ordered pass groups
/// (see `doc/ORDERING.md`), so one invocation produces the fully modernized
/// result even when a pass only becomes applicable after an earlier pass has
/// rewritten the code: for example, dot-shorthands collapsing the value arms of
/// a switch expression that switch-expressions just produced. Each case asserts
/// that converged output from a single run, and that a second run changes
/// nothing.
library;

import 'package:test/test.dart';

import '../support/cli_harness.dart';

const _file = 'lib/c.dart';

void main() {
  group('passes compose to a fixpoint in one run', () {
    _composes(
      'switch-expressions, expression-bodies and dot-shorthands turn a '
      'statement switch into an arrow-bodied switch expression with shorthands',
      passes: {'switch_expressions', 'expression_bodies', 'dot_shorthands'},
      input: '''
class Token {
  final String value;
  Token(this.value);
}

Token parse(int code) {
  switch (code) {
    case 0:
      return Token('zero');
    default:
      return Token('other');
  }
}
''',
      expected: '''
class Token {
  final String value;
  Token(this.value);
}

Token parse(int code) => switch (code) {
  0 => .new('zero'),
  _ => .new('other'),
};
''',
    );

    _composes(
      'cascades folds a write run and inline-return drops the freed local',
      passes: {'cascades', 'inline_return'},
      input: '''
class Conn {
  void open() {}
  void send(String s) {}
}

Conn build(String token) {
  var c = Conn();
  c.open();
  c.send(token);
  return c;
}
''',
      expected: '''
class Conn {
  void open() {}
  void send(String s) {}
}

Conn build(String token) {
  return Conn()
    ..open()
    ..send(token);
}
''',
    );

    _composes(
      'cascades, prefer-inferred-types and dot-shorthands fold a typed list '
      'builder into a cascade with inferred type and shorthands',
      passes: {'cascades', 'prefer_inferred_types', 'dot_shorthands'},
      input: '''
enum Mode { fast, slow }

void configure() {
  final List<Mode> settings = [];
  settings.add(Mode.fast);
  settings.add(Mode.slow);
  print(settings);
}
''',
      expected: '''
enum Mode { fast, slow }

void configure() {
  final settings = <Mode>[]
    ..add(.fast)
    ..add(.slow);
  print(settings);
}
''',
    );

    _composes(
      'expression-bodies and dot-shorthands collapse a block-return of an '
      'enum value',
      passes: {'expression_bodies', 'dot_shorthands'},
      input: '''
enum Color { red, blue }

Color pick() {
  return Color.red;
}
''',
      expected: '''
enum Color { red, blue }

Color pick() => .red;
''',
    );

    _composes(
      'prefer-inferred-types drops the annotation and final-locals upgrades '
      'the resulting var',
      passes: {'prefer_inferred_types', 'final_locals'},
      input: '''
class Foo {}

Foo makeFoo() => Foo();

void main() {
  Foo f = makeFoo();
  print(f);
}
''',
      expected: '''
class Foo {}

Foo makeFoo() => Foo();

void main() {
  final f = makeFoo();
  print(f);
}
''',
    );

    _composes(
      'super-parameters and dot-shorthands fold a partially forwarded super '
      'call',
      passes: {'super_parameters', 'dot_shorthands'},
      input: '''
enum Level { low, high }

class Base {
  final Level level;
  final int weight;
  Base({required this.level, required this.weight});
}

class Derived extends Base {
  Derived({required int weight}) : super(level: Level.low, weight: weight);
}
''',
      expected: '''
enum Level { low, high }

class Base {
  final Level level;
  final int weight;
  Base({required this.level, required this.weight});
}

class Derived extends Base {
  Derived({required super.weight}) : super(level: .low);
}
''',
    );

    _composes(
      'null-aware-spread, string-interpolation and dot-shorthands all apply '
      'to one file',
      passes: {'null_aware_spread', 'string_interpolation', 'dot_shorthands'},
      input: '''
enum Flag { on, off }

String describe(String label, List<int>? extra) {
  final parts = [1, if (extra != null) ...extra];
  final joined = parts.length.toString();
  return 'count: ' + label + joined;
}

Flag current() => Flag.on;
''',
      expected: '''
enum Flag { on, off }

String describe(String label, List<int>? extra) {
  final parts = [1, ...?extra];
  final joined = parts.length.toString();
  return 'count: \$label\$joined';
}

Flag current() => .on;
''',
    );

    _composes(
      'expression-bodies and string-interpolation collapse a block-return '
      'concatenation',
      passes: {'expression_bodies', 'string_interpolation'},
      input: '''
String greet(String name) {
  return 'Hello, ' + name + '!';
}
''',
      expected: '''
String greet(String name) => 'Hello, \$name!';
''',
    );
  });
}

/// Registers a test that runs the CLI with only [passes] enabled and asserts the
/// file converges to [expected] in a single run, then stays put on a re-run.
void _composes(
  String description, {
  required Set<String> passes,
  required String input,
  required String expected,
}) {
  test(description, () async {
    final project = createProject(files: {_file: input});
    final args = onlyFeaturesArgs(passes);

    final run1 = await invokeCli(project, args: args);
    expect(run1.exitCode, 0, reason: run1.stderr);
    expect(run1.read(_file), expected, reason: 'one run should fully converge');

    final run2 = await invokeCli(project, args: args);
    expect(run2.exitCode, 0, reason: run2.stderr);
    expect(run2.read(_file), expected, reason: 'a second run must be a no-op');
  });
}
