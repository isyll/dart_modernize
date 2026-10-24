/// Minimal source snippets that each exercise exactly **one** transformation
/// pass, used by the CLI behaviour tests.
///
/// Every trigger is crafted so that only its own pass would modify it; each
/// other pass must leave it byte-for-byte unchanged. That property is what makes
/// "disabling a flag skips exactly its pass" observable: run with `--no-<flag>`
/// (every other pass still on) and the trigger must be untouched.
library;

const abstractFinalClassesTrigger = '''
class Constants {
  static const maxRetries = 3;
}
''';

const cascadesTrigger = '''
Box makeBox() {
  final b = Box();
  b.width = 10;
  b.height = 20;
  return b;
}

class Box {
  int width = 0;
  int height = 0;
}
''';

const dotShorthandsTrigger = '''
E pick() => E.a;

enum E { a, b }
''';

const expressionBodiesTrigger = '''
int square(int x) {
  return x * x;
}
''';

const finalLocalsTrigger = '''
int compute() => 42;

int result() {
  var x = compute();
  return x.abs();
}
''';

/// Analysis options enabling the lints the fix-all trigger relies on.
const fixAllLints = '''
linter:
  rules:
    - annotate_overrides
    - prefer_final_locals
    - unnecessary_new
''';

const fixAllTrigger = '''
class A {
  String f() => '';
}

class B extends A {
  String f() => 'x';
}
''';

const inlineReturnTrigger = '''
int compute() => 42;

int result() {
  final x = compute();
  return x;
}
''';

const nullAwareElementsTrigger = '''
List<int?> pack(int? a) => [if (a != null) a];
''';

const nullAwareSpreadTrigger = '''
List<int> merge(List<int> base, List<int>? extra) {
  final result = [...base, if (extra != null) ...extra];
  return result.toList();
}
''';

const organizeImportsTrigger = '''
import 'dart:math';
import 'dart:convert';

String f(num n) => jsonEncode(n * pi);
''';

/// A top-level const with a redundant explicit type; only prefer_inferred_types
/// would remove it. No other pass touches a top-level const declaration.
const preferInferredTypesTrigger = '''
const int timeout = 30;
''';

/// Already in the `new(...)` form, so constructor-shorthands has nothing to
/// do here.
const primaryConstructorsTrigger = '''
class P {
  new(this.x, this.y);

  final int x;
  final int y;
}
''';

/// The doc comment keeps primary-constructors away: it would otherwise move
/// `_x = x` onto the field itself.
const privateNamedParametersTrigger = '''
class C {
  /// Creates a C.
  new({required int x}) : _x = x;

  final int _x;

  int get x => _x;
}
''';

/// The doc comment keeps primary-constructors away: it would otherwise move
/// `this.id = id` onto the field and promote the class.
const sortConstructorsFirstTrigger = '''
class Marker {
  final int id;

  /// Creates a marker.
  new(int id) : this.id = id;
}
''';

const sortMembersTrigger = '''
class S {
  void beta() {}

  void alpha() {}
}
''';

const stringInterpolationTrigger = '''
String greet(String name) => 'Hello, ' + name + '!';
''';

const superParametersTrigger = '''
class Base {
  new({required this.id});

  final int id;
}

class Derived extends Base {
  new({required int id}) : super(id: id);
}
''';

const switchExpressionsTrigger = '''
int classify(int code) {
  int result;
  switch (code) {
    case 0:
      result = 10;
      break;
    default:
      result = 20;
  }
  return result;
}
''';

const nullAwareConditionalsTrigger = '''
int? first(List<int>? xs) => xs == null ? null : xs[0];
''';

const destructureForInTrigger = '''
void report(Map<String, int> scores) {
  for (final entry in scores.entries) {
    print(entry.key);
  }
}
''';

/// Uses a record rather than a class. A small class with final fields and one
/// constructor is exactly what primary-constructors promotes, which would make
/// another pass touch this trigger and fail the check for the wrong reason.
const destructureLocalsTrigger = '''
(int, int) pair() => (1, 2);

int sum() {
  final p = pair();
  final a = p.\$1;
  final b = p.\$2;
  return a + b;
}
''';

/// Guarded with an `if` rather than a plain run of `add` calls, because a plain
/// run is also what `cascades` folds. Without the `if`, a default run would
/// rewrite this anyway and the "stays off by default" check would prove nothing.
const collectionElementsTrigger = '''
List<int> build(bool flag) {
  final items = <int>[];
  if (flag) items.add(1);
  return items;
}
''';

/// Two generative constructors, so primary-constructors leaves the class.
const constructorShorthandsTrigger = '''
class Point {
  Point(this.x);
  Point.origin() : x = 0;

  final int x;
}
''';

/// `implements` keeps abstract-final-classes away from the empty class.
const emptyBodiesTrigger = '''
class NetworkException implements Exception {}
''';

/// Two statements, so expression-bodies has nothing to collapse, and a
/// duration from a parameter, which dot-shorthands has nothing to shorten in.
const futurePauseTrigger = '''
Future<void> settle(Duration delay) async {
  await Future.delayed(delay);
  print('settled');
}
''';

const wildcardParametersTrigger = '''
String separator(int _, String __) => '-';
''';

const nullAwareCallsTrigger = '''
void notify(void Function(int)? onChanged) {
  if (onChanged != null) onChanged(1);
}
''';

/// No context type, so dot-shorthands leaves the constructor call alone.
const unmodifiableOfTrigger = '''
final ids = <int>[1, 2];
final frozen = List<int>.unmodifiable(ids);
''';

/// Trigger source keyed by feature folder name.
const triggers = <String, String>{
  'dot_shorthands': dotShorthandsTrigger,
  'private_named_parameters': privateNamedParametersTrigger,
  'primary_constructors': primaryConstructorsTrigger,
  'super_parameters': superParametersTrigger,
  'switch_expressions': switchExpressionsTrigger,
  'cascades': cascadesTrigger,
  'inline_return': inlineReturnTrigger,
  'final_locals': finalLocalsTrigger,
  'prefer_inferred_types': preferInferredTypesTrigger,
  'expression_bodies': expressionBodiesTrigger,
  'string_interpolation': stringInterpolationTrigger,
  'null_aware_spread': nullAwareSpreadTrigger,
  'null_aware_elements': nullAwareElementsTrigger,
  'null_aware_conditionals': nullAwareConditionalsTrigger,
  'destructure_for_in': destructureForInTrigger,
  'destructure_locals': destructureLocalsTrigger,
  'collection_elements': collectionElementsTrigger,
  'organize_imports': organizeImportsTrigger,
  'sort_members': sortMembersTrigger,
  'sort_constructors_first': sortConstructorsFirstTrigger,
  'fix_all': fixAllTrigger,
  'abstract_final_classes': abstractFinalClassesTrigger,
  'constructor_shorthands': constructorShorthandsTrigger,
  'empty_bodies': emptyBodiesTrigger,
  'future_pause': futurePauseTrigger,
  'wildcard_parameters': wildcardParametersTrigger,
  'null_aware_calls': nullAwareCallsTrigger,
  'unmodifiable_of': unmodifiableOfTrigger,
};

/// Project files for [feature]'s isolated trigger (source plus any extra config
/// that pass needs to fire).
Map<String, String> triggerFiles(String feature) => {
  'lib/trigger.dart': triggers[feature]!,
  if (feature == 'fix_all') 'analysis_options.yaml': fixAllLints,
};
