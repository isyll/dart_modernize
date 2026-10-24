/// Semantic-safety spec: modernization changes syntax, never meaning.
///
/// A clean, hand-written sample is analyzed (it must start clean), modernized by
/// the real CLI, then analyzed again, and it must *still* analyze without any
/// error or warning. This guards against a transformation that produces output
/// which no longer compiles or type-checks.
///
/// The first case runs every pass but primary constructors; the second covers
/// that one on its own. Splitting them keeps each sample small enough to read.
///
/// The second case earns its keep: golden files are compared byte for byte but
/// never compiled, so this is the only check that promoted classes are still
/// valid Dart.
library;

import 'package:test/test.dart';

import '../support/analysis_helper.dart';
import '../support/cli_harness.dart';

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
      files: {
        'lib/models.dart': _primaryConstructorSample,
        'lib/callers.dart': _primaryConstructorCallers,
      },
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
    for (final header in [
      'class Pair(',
      'class Config({',
      'class const CartState(',
      'class Range(',
      'class Scaled(',
      'class const Vec._(',
      'enum Planet(',
    ]) {
      expect(produced, contains(header), reason: header);
    }
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

class Pair {
  final int a;
  final int b;

  Pair(this.a, [this.b = 2]);
}

class Config {
  final String host;
  final int port;
  final Duration? timeout;

  Config({required this.host, this.port = 8080, this.timeout = const Duration(seconds: 5)});
}

class CartState {
  final List<String> items;
  final int total;

  const CartState(this.total, {this.items = const []});
}

class Range {
  final int min;
  final int max;

  Range(this.min, this.max) : assert(min <= max);
}

class Scaled {
  final int _value;

  Scaled(int raw) : _value = raw * 2;

  int get value => _value;
}

class Vec {
  final int x;
  final int y;

  const Vec._(this.x, this.y);

  factory Vec.zero() => const Vec._(0, 0);
  Vec.unit() : this._(1, 1);
}

enum Planet {
  mercury(3.3),
  venus(4.8);

  const Planet(this.mass);

  final double mass;
}
''';

/// Callers in another file, which break when a promotion changes a
/// constructor's signature (a dropped default or `[...]`) even though the
/// promoted file itself still compiles.
const _primaryConstructorCallers = '''
import 'models.dart';

void callers() {
  print(Pair(1).b);
  print(Config(host: 'x').port);
  print(Config(host: 'x').timeout?.inSeconds);
  print(const CartState(0).items);
  print(Range(1, 2).max);
  print(Scaled(3).value);
  print([Vec.zero(), Vec.unit()]);
  print(Planet.venus.mass);
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
