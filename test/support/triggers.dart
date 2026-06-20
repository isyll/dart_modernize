/// Minimal source snippets that each exercise exactly **one** transformation
/// pass, used by the CLI behaviour tests.
///
/// Every trigger is crafted so that only its own pass would modify it; each
/// other pass must leave it byte-for-byte unchanged. That property is what makes
/// "disabling a flag skips exactly its pass" observable: run with `--no-<flag>`
/// (every other pass still on) and the trigger must be untouched.
library;

import 'cli_harness.dart';

const String cascadesTrigger = '''
Box makeBox() {
  var b = Box();
  b.width = 10;
  b.height = 20;
  return b;
}

class Box {
  int width = 0;
  int height = 0;
}
''';

const String dotShorthandsTrigger = '''
E pick() => E.a;

enum E { a, b }
''';

const String expressionBodiesTrigger = '''
int square(int x) {
  return x * x;
}
''';

/// Analysis options enabling the lints the fix-all trigger relies on.
const String fixAllLints = '''
linter:
  rules:
    - annotate_overrides
    - prefer_final_locals
    - unnecessary_new
''';

const String fixAllTrigger = '''
class A {
  String f() => '';
}

class B extends A {
  String f() => 'x';
}
''';

const String nullAwareElementsTrigger = '''
List<int?> pack(int? a) {
  final result = [if (a != null) a];
  return result;
}
''';

const String nullAwareSpreadTrigger = '''
List<int> merge(List<int> base, List<int>? extra) {
  final result = [...base, if (extra != null) ...extra];
  return result;
}
''';

const String organizeImportsTrigger = '''
import 'dart:math';
import 'dart:convert';

String f(num n) => jsonEncode(n * pi);
''';

const String primaryConstructorsTrigger = '''
class P {
  final int x;
  final int y;

  P(this.x, this.y);
}
''';

const String privateNamedParametersTrigger = '''
class C {
  final int _x;

  C({required int x}) : _x = x;

  int get x => _x;
}
''';

/// A pubspec opting into the language version primary constructors require.
const String pubspec313 = '''
name: fixture_project
environment:
  sdk: ">=3.13.0 <4.0.0"
''';

const String sortMembersTrigger = '''
class S {
  void m() {}

  final int x = 0;
}
''';

const String stringInterpolationTrigger = '''
String greet(String name) {
  final msg = 'Hello, ' + name + '!';
  return msg;
}
''';

const String superParametersTrigger = '''
class Base {
  final int id;

  Base({required this.id});
}

class Derived extends Base {
  Derived({required int id}) : super(id: id);
}
''';

const String switchExpressionsTrigger = '''
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

/// Trigger source keyed by feature folder name.
const Map<String, String> triggers = {
  'dot_shorthands': dotShorthandsTrigger,
  'private_named_parameters': privateNamedParametersTrigger,
  'primary_constructors': primaryConstructorsTrigger,
  'super_parameters': superParametersTrigger,
  'switch_expressions': switchExpressionsTrigger,
  'cascades': cascadesTrigger,
  'expression_bodies': expressionBodiesTrigger,
  'string_interpolation': stringInterpolationTrigger,
  'null_aware_spread': nullAwareSpreadTrigger,
  'null_aware_elements': nullAwareElementsTrigger,
  'organize_imports': organizeImportsTrigger,
  'sort_members': sortMembersTrigger,
  'fix_all': fixAllTrigger,
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
