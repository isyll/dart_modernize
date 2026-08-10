/// Minimal source snippets that each exercise exactly **one** transformation
/// pass, used by the CLI behaviour tests.
///
/// Every trigger is crafted so that only its own pass would modify it; each
/// other pass must leave it byte-for-byte unchanged. That property is what makes
/// "disabling a flag skips exactly its pass" observable: run with `--no-<flag>`
/// (every other pass still on) and the trigger must be untouched.
library;

import 'cli_harness.dart';

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

const primaryConstructorsTrigger = '''
class P {
  P(this.x, this.y);

  final int x;
  final int y;
}
''';

const privateNamedParametersTrigger = '''
class C {
  C({required int x}) : _x = x;

  final int _x;

  int get x => _x;
}
''';

/// A pubspec opting into the language version primary constructors require.
const pubspec313 = '''
name: fixture_project
environment:
  sdk: ">=3.13.0 <4.0.0"
''';

const sortConstructorsFirstTrigger = '''
class Marker {
  final int id;

  Marker(int id) : this.id = id;
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
  Base({required this.id});

  final int id;
}

class Derived extends Base {
  Derived({required int id}) : super(id: id);
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

/// The point is taken as a parameter rather than built by a helper. A helper
/// like `Point getPoint() => const Point(1, 2);` is a dot-shorthand target, so
/// dot-shorthands would rewrite it to `const .new(1, 2)` and the "only its own
/// pass may touch this trigger" check would fail for the wrong reason.
const destructureLocalsTrigger = '''
class Point {
  const Point(this.x, this.y);
  final int x;
  final int y;
}

int sum(Point point) {
  final p = point;
  final x = p.x;
  final y = p.y;
  return x + y;
}
''';

/// Deliberately guarded with an `if` rather than a plain run of `add` calls.
/// A bare run is also exactly what `cascades` folds, so a default run (where
/// collection-elements is off but cascades is on) would rewrite it anyway and
/// the "stays off by default" check could never tell the two apart.
const collectionElementsTrigger = '''
List<int> build(bool flag) {
  final items = <int>[];
  if (flag) items.add(1);
  return items;
}
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
};

/// Project files for [feature]'s isolated trigger (source plus any extra config
/// that pass needs to fire).
Map<String, String> triggerFiles(String feature) => {
  'lib/trigger.dart': triggers[feature]!,
  if (feature == 'fix_all') 'analysis_options.yaml': fixAllLints,
};

/// The pubspec [feature]'s trigger should run under.
String triggerPubspec(String feature) =>
    feature == 'primary_constructors' ? pubspec313 : defaultPubspec;
