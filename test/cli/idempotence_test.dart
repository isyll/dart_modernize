/// Behavioural spec: the tool is idempotent.
///
/// Modernization must converge in one run and stay put forever after. The first
/// run must change the file; every subsequent run must be a byte-for-byte no-op,
/// checked three runs deep.
library;

import 'package:test/test.dart';

import '../support/cli_harness.dart';

void main() {
  test('first run modernizes, then further runs change nothing', () async {
    final project = createProject(files: {'lib/a.dart': _multiPass});

    final run1 = await invokeCli(project);
    expect(run1.exitCode, 0, reason: run1.stderr);
    final afterFirst = run1.read('lib/a.dart');
    expect(
      afterFirst,
      isNot(_multiPass),
      reason: 'the first run should modernize the file',
    );

    for (var pass = 2; pass <= 3; pass++) {
      final rerun = await invokeCli(project);
      expect(rerun.exitCode, 0, reason: rerun.stderr);
      expect(
        rerun.read('lib/a.dart'),
        afterFirst,
        reason: 'run #$pass must be a no-op on already-modernized code',
      );
    }
  });
}

/// Exercises many passes at once so idempotence is checked across their
/// interaction, not just one in isolation: prefer-inferred-types drops the
/// `final Logger` annotation, dot-shorthands collapses an enum field initializer
/// and an assignment target, private-named-parameters folds `this._retries`,
/// expression-bodies arrows `toggle`, and sort-members reorders the members.
const _multiPass = '''
import 'dart:convert';

enum Mode { fast, slow }

class Logger {}

class Config {
  final Logger _logger = Logger();
  final int _retries;

  Config({required int retries}) : _retries = retries;

  Mode _mode = Mode.fast;

  void toggle() {
    _mode = Mode.slow;
  }

  Mode mode() => _mode;

  int get retries => _retries;

  Logger get logger => _logger;
}

String dump(Object o) => jsonEncode(o);
''';
