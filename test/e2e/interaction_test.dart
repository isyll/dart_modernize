/// Cross-feature interaction spec.
///
/// The golden suites exercise one pass at a time. This suite covers what happens
/// when several passes apply to the same file, and often the same construct, in
/// a single run.
///
/// One run produces the finished result even when a pass only applies after an
/// earlier pass has rewritten the code (for example, dot-shorthands collapsing
/// the value arms of a switch expression that switch-expressions produced). Each
/// case checks that result from a single run, and that a second run is a no-op.
library;

import 'package:test/test.dart';

import '../support/cli_harness.dart';

void main() {
  group('passes combine in a single run', () {
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
      'prefer-inferred-types drops the obvious annotation and final-locals '
      'upgrades the resulting var',
      passes: {'prefer_inferred_types', 'final_locals'},
      input: '''
void main() {
  int count = 42;
  print(count);
}
''',
      expected: '''
void main() {
  final count = 42;
  print(count);
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

    _composes(
      'prefer-inferred-types drops a redundant field type so dot-shorthands '
      'never introduces a .new',
      passes: {'prefer_inferred_types', 'dot_shorthands'},
      input: '''
class Provider {
  Provider(this.id);
  final int id;
}

class Holder {
  final Provider provider = Provider(1);
}
''',
      expected: '''
class Provider {
  Provider(this.id);
  final int id;
}

class Holder {
  final provider = Provider(1);
}
''',
    );

    _composes(
      'dot-shorthands collapses an assignment target inside the body '
      'expression-bodies produces',
      passes: {'dot_shorthands', 'expression_bodies'},
      input: '''
enum Mode { fast, slow }

class Engine {
  Mode mode = Mode.fast;

  void boost() {
    mode = Mode.slow;
  }
}
''',
      expected: '''
enum Mode { fast, slow }

class Engine {
  Mode mode = .fast;

  void boost() => mode = .slow;
}
''',
    );

    _composes(
      'null-aware-conditionals folds the conditional and dot-shorthands then '
      'collapses the fallback arm it produced',
      passes: {'null_aware_conditionals', 'dot_shorthands'},
      input: '''
enum Color { red, blue }

class Box {
  Color get color => Color.blue;
}

Color pick(Box? box) => box != null ? box.color : Color.red;
''',
      expected: '''
enum Color { red, blue }

class Box {
  Color get color => Color.blue;
}

Color pick(Box? box) => box?.color ?? .red;
''',
    );
  });

  group('final-locals and fix-all on the same for-in loop', () {
    // `prefer_final_in_for_each` makes `dart fix` want the exact edit
    // final-locals makes, so this is the one construct the two passes could
    // fight over. They cannot: final-locals runs in the transform stage and
    // fix-all runs later over the finalized file, where the loop already reads
    // `final` and `dart fix` reports nothing.
    const options = '''
linter:
  rules:
    - prefer_final_in_for_each
''';
    const input = '''
void use(int value) {}

void loop(List<int> xs) {
  for (var x in xs) {
    use(x);
  }
}
''';
    const expected = '''
void use(int value) {}

void loop(List<int> xs) {
  for (final x in xs) {
    use(x);
  }
}
''';

    test('produce the lint fix exactly once and stay idempotent', () async {
      final project = createProject(
        files: {_file: input, 'analysis_options.yaml': options},
      );
      final args = onlyFeaturesArgs({'final_locals', 'fix_all'});

      final run1 = await invokeCli(project, args: args);
      expect(run1.exitCode, 0, reason: run1.stderr);
      expect(run1.read(_file), expected, reason: 'no double edit, no conflict');

      final run2 = await invokeCli(project, args: args);
      expect(run2.exitCode, 0, reason: run2.stderr);
      expect(
        run2.read(_file),
        expected,
        reason: 'a second run changes nothing',
      );
    });

    test(
      'fix-all alone reaches the same bytes final-locals produces',
      () async {
        final project = createProject(
          files: {_file: input, 'analysis_options.yaml': options},
        );

        final result = await invokeCli(
          project,
          args: onlyFeaturesArgs({'fix_all'}),
        );
        expect(result.exitCode, 0, reason: result.stderr);
        expect(result.read(_file), expected);
      },
    );
  });
}

const _file = 'lib/c.dart';

/// Registers a test that runs the CLI with only [passes] enabled and asserts the
/// file reaches [expected] in a single run, then stays put on a re-run.
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
    expect(run1.read(_file), expected, reason: 'one run should be enough');

    final run2 = await invokeCli(project, args: args);
    expect(run2.exitCode, 0, reason: run2.stderr);
    expect(run2.read(_file), expected, reason: 'a second run must be a no-op');
  });
}
