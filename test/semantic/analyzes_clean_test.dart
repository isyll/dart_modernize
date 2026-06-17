/// Semantic-safety spec: modernization changes syntax, never meaning.
///
/// A clean, hand-written sample is analyzed (it must start clean), modernized by
/// the real CLI, then analyzed again — and it must *still* analyze without any
/// error or warning. This guards against a transformation that produces output
/// which no longer compiles or type-checks.
///
/// Primary constructors are excluded here: their output requires a newer,
/// experimental language version that the default fixture project does not opt
/// into. Every other pass produces code valid under the package's own SDK floor.
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
}

/// Idiomatic, warning-free code that several passes would still modernize
/// (dot shorthands on `Mode.fast`, a private named parameter for `_name`).
const String _sample = '''
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
