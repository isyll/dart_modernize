/// Behavioural spec: the tool is idempotent.
///
/// Modernization must converge — running it on already-modernized code makes no
/// further edits. The test runs the CLI twice against the same project: the
/// first pass must change something, the second pass must change nothing.
library;

import 'package:test/test.dart';

import '../support/cli_harness.dart';

void main() {
  test('running twice produces no second-run changes', () async {
    final project = createProject(files: {'lib/a.dart': _multiPass});

    final run1 = await invokeCli(project);
    final afterFirst = run1.read('lib/a.dart');

    final run2 = await invokeCli(project);
    final afterSecond = run2.read('lib/a.dart');

    expect(run1.exitCode, 0, reason: run1.stderr);
    expect(run2.exitCode, 0, reason: run2.stderr);

    expect(
      afterFirst,
      isNot(_multiPass),
      reason: 'the first run should modernize the file',
    );
    expect(
      afterSecond,
      afterFirst,
      reason: 'the second run must be a no-op on already-modernized code',
    );
  });
}

/// Exercises several passes at once (import pruning + sorting, dot shorthands,
/// private named parameters, and member sorting) so idempotence is checked
/// across passes, not just one.
const String _multiPass = '''
import 'dart:math';
import 'dart:convert';

enum Mode { fast, slow }

class Config {
  final int _retries;

  Config({required int retries}) : _retries = retries;

  Mode mode() => Mode.fast;

  int get retries => _retries;
}

String dump(Object o) => jsonEncode(o);
''';
