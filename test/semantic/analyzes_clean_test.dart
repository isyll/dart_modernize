/// Semantic-safety spec: modernization changes syntax, never meaning.
///
/// A clean, hand-written sample is analyzed (it must start clean), modernized by
/// the real CLI, then analyzed again, and it must *still* analyze without any
/// error or warning. This guards against a transformation that produces output
/// which no longer compiles or type-checks.
///
/// The first case excludes primary constructors, whose output needs language
/// version 3.13 while the default fixture project sits on the package's SDK
/// floor. The second case covers them on their own, against a 3.13 project.
/// That second case matters more than it looks: golden `.expected` files
/// deliberately drop the `.dart` extension so no tool reads them, which means a
/// golden pass proves the bytes match but never that they compile. This is the
/// only check that primary-constructor output is real Dart.
library;

import 'package:test/test.dart';

import '../support/analysis_helper.dart';
import '../support/cli_harness.dart';
import '../support/triggers.dart';

void main() {
  test('a modernized project still analyzes without errors', () async {
    final project = createProject(files: {'lib/app.dart': _sample});

    final before = await analyzeProject(project);
    expect(
      before.exitCode,
      0,
      reason: 'the sample must start clean:\n${before.output}',
    );

    final run = await invokeCli(
      project,
      args: const ['--no-primary-constructors'],
    );
    expect(run.exitCode, 0, reason: run.stderr);

    final after = await analyzeProject(project);
    expect(
      after.exitCode,
      0,
      reason: 'the modernized project must analyze clean:\n${after.output}',
    );
  });

  test('promoted primary constructors still analyze without errors', () async {
    final project = createProject(
      files: {'lib/models.dart': _primaryConstructorSample},
      pubspec: pubspec313,
    );

    final before = await analyzeProject(project);
    expect(
      before.exitCode,
      0,
      reason: 'the sample must start clean:\n${before.output}',
    );

    final run = await invokeCli(
      project,
      args: onlyFeatureArgs('primary_constructors'),
    );
    expect(run.exitCode, 0, reason: run.stderr);

    final after = await analyzeProject(project);
    expect(
      after.exitCode,
      0,
      reason:
          'promoted classes must still compile:\n${after.output}\n'
          '--- produced ---\n${run.read('lib/models.dart')}',
    );

    // Guard against the test passing because nothing was promoted at all.
    final produced = run.read('lib/models.dart');
    expect(produced, contains('class Point('), reason: 'plain promotion');
    expect(
      produced,
      contains('class const Origin('),
      reason: 'const promotion',
    );
  });
}

/// Classes the promotion applies to, including the const form that is only
/// expressible since primary constructors went stable in Dart 3.13.
const _primaryConstructorSample = '''
class Point {
  final int x;
  final int y;

  Point(this.x, this.y);
}

class Origin {
  final int x;

  const Origin(this.x);
}

class Counter {
  int count;

  Counter(this.count);
}

void use() {
  const origin = Origin(0);
  print([Point(1, 2), origin, Counter(3)]);
}
''';

/// Idiomatic, warning-free code that several passes would still modernize
/// (dot shorthands on `Mode.fast`, a private named parameter for `_name`).
const _sample = '''
import 'dart:convert';

enum Mode { fast, slow }

class Settings {
  final String _name;

  Settings({required String name}) : _name = name;

  String get name => _name;

  Mode mode() => Mode.fast;

  String encode() => jsonEncode({'name': _name});
}
''';
