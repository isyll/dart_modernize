/// Minimal source snippets that each exercise exactly **one** transformation
/// pass, used by the CLI behaviour tests.
///
/// Every trigger is crafted so that only its own pass would modify it — each
/// other pass must leave it byte-for-byte unchanged. That property is what makes
/// "disabling a flag skips exactly its pass" observable: run with `--no-<flag>`
/// (every other pass still on) and the trigger must be untouched.
library;

import 'cli_harness.dart';

const String dotShorthandsTrigger = '''
enum E { a, b }

E pick() => E.a;
''';

const String privateNamedParametersTrigger = '''
class C {
  final int _x;

  C({required int x}) : _x = x;

  int get x => _x;
}
''';

const String primaryConstructorsTrigger = '''
class P {
  final int x;
  final int y;

  P(this.x, this.y);
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

const String organizeImportsTrigger = '''
import 'dart:math';
import 'dart:convert';

String f(Object o) => jsonEncode(o);
''';

const String sortMembersTrigger = '''
class S {
  void m() {}

  final int x = 0;
}
''';

const String fixAllTrigger = '''
class A {
  String f() => '';
}

class B extends A {
  String f() => 'x';
}
''';

/// Trigger source keyed by feature folder name.
const Map<String, String> triggers = {
  'dot_shorthands': dotShorthandsTrigger,
  'private_named_parameters': privateNamedParametersTrigger,
  'primary_constructors': primaryConstructorsTrigger,
  'switch_expressions': switchExpressionsTrigger,
  'organize_imports': organizeImportsTrigger,
  'sort_members': sortMembersTrigger,
  'fix_all': fixAllTrigger,
};

/// Analysis options enabling the lints the fix-all trigger relies on.
const String fixAllLints = '''
linter:
  rules:
    - annotate_overrides
    - prefer_final_locals
    - unnecessary_new
''';

/// A pubspec opting into the language version primary constructors require.
const String pubspec313 = '''
name: fixture_project
environment:
  sdk: ">=3.13.0 <4.0.0"
''';

/// Project files for [feature]'s isolated trigger (source plus any extra config
/// that pass needs to fire).
Map<String, String> triggerFiles(String feature) => {
  'lib/trigger.dart': triggers[feature]!,
  if (feature == 'fix_all') 'analysis_options.yaml': fixAllLints,
};

/// The pubspec [feature]'s trigger should run under.
String triggerPubspec(String feature) =>
    feature == 'primary_constructors' ? pubspec313 : defaultPubspec;
