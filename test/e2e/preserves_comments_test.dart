/// Modernization rewrites code, never documentation.
///
/// The three bugs this guards against all came from the same place: a pass
/// rebuilt a construct from its parts and quietly left the comments behind.
/// Promoting a primary constructor dropped a field's doc comment, dropped an
/// annotation, and dropped the `//` comment above a member it kept.
///
/// The per-pass fixtures pin those three cases. This one is the general rule:
/// run the whole pipeline over a file full of comments and require every single
/// one to still be there. Any pass that starts deleting comments fails here,
/// including a pass that does not exist yet.
library;

import 'package:test/test.dart';

import '../support/cli_harness.dart';

void main() {
  test('every comment survives a full run', () async {
    final project = createProject(files: {'lib/app.dart': _commented});
    final run = await invokeCli(project);
    expect(run.exitCode, 0, reason: run.stderr);

    final after = run.read('lib/app.dart');
    for (final comment in _commentsIn(_commented)) {
      expect(
        after,
        contains(comment),
        reason: 'the run deleted this comment: $comment',
      );
    }
  });

  test('the run actually rewrote something', () async {
    // Without this, the test above would still pass on a tool that does
    // nothing at all.
    final project = createProject(files: {'lib/app.dart': _commented});
    final run = await invokeCli(project);
    expect(run.read('lib/app.dart'), isNot(_commented));
  });
}

/// Every `//` and `///` line in [source], trimmed.
List<String> _commentsIn(String source) => [
  for (final line in source.split('\n'))
    if (line.trim().startsWith('//')) line.trim(),
];

/// Comments on a class, a field, a method, a getter and a top-level function,
/// over code that several passes rewrite: dot-shorthands on `Mode.fast`,
/// string-interpolation and expression-bodies on `greet`.
const _commented = '''
/// How fast the worker runs.
enum Mode { fast, slow }

/// Settings for a single run.
class Settings {
  /// Name shown to the user.
  final String name;

  Settings({required this.name});

  // Mutable so the UI can flip it between runs.
  Mode mode = Mode.fast;

  /// Label for the settings row.
  String get label => name;
}

/// Greets the user by name.
String greet(String name) {
  return 'Hello, ' + name + '!';
}
''';
