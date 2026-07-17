/// Unit spec for parsing `git status --porcelain` into tracked-change lines.
library;

import 'package:dart_modernize/src/vcs/git_worktree.dart';
import 'package:test/test.dart';

void main() {
  group('parseTrackedChanges', () {
    test(
      'keeps modified and staged tracked entries',
      () => expect(parseTrackedChanges(' M lib/a.dart\nA  lib/b.dart\n'), [
        ' M lib/a.dart',
        'A  lib/b.dart',
      ]),
    );

    test(
      'drops untracked ?? entries',
      () => expect(parseTrackedChanges('?? lib/new.dart\n'), isEmpty),
    );

    test(
      'keeps tracked entries but drops untracked and blank lines',
      () => expect(
        parseTrackedChanges(' M a.dart\n?? b.dart\n\nR  old -> new\n'),
        [' M a.dart', 'R  old -> new'],
      ),
    );

    test(
      'a clean tree yields nothing',
      () => expect(parseTrackedChanges(''), isEmpty),
    );
  });
}
