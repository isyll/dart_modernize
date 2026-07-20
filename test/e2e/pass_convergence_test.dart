/// Convergence spec: passes must agree, never undo one another.
///
/// The tool has to reach a *fixed point*. Once a file is fully modernized,
/// running any single pass over it again must change nothing. A regression here
/// looked like two passes with opposite ideas about the same thing, each undoing
/// the other forever:
///
///   dart_modernize sort-members             # put fields before constructors
///   dart_modernize sort-constructors-first  # put constructors before fields
///
/// Running one after the other flip-flopped every affected file, so the tool
/// never settled. These tests pin the contract: `sort-members` already emits the
/// constructors-first order that `sort-constructors-first` wants, so neither can
/// undo the other, and after a full run every region-rewriting finalize pass is
/// a byte-for-byte no-op.
library;

import 'package:test/test.dart';

import '../support/cli_harness.dart';

void main() {
  group('sort-members and sort-constructors-first never fight', () {
    // A class whose members are deliberately scrambled: a method first, then an
    // instance field, a static field, an unnamed constructor, a getter, and a
    // named constructor last.
    const scrambled = '''
class Account {
  void deposit(int n) {}

  final String id;
  static int total = 0;

  Account(this.id);

  int get balance => 0;

  Account.empty() : this('');
}
''';

    test(
      'sort-members output already satisfies sort-constructors-first',
      () async {
        final project = createProject(files: {'lib/a.dart': scrambled});

        final sorted = await invokeCli(
          project,
          args: onlyFeatureArgs('sort_members'),
        );
        expect(sorted.exitCode, 0, reason: sorted.stderr);
        final afterMembers = sorted.read('lib/a.dart');

        // sort-members must place both constructors before every other member.
        expect(
          afterMembers,
          stringContainsInOrder([
            'Account(this.id);',
            'Account.empty()',
            'static int total',
            'final String id',
            'int get balance',
            'void deposit',
          ]),
          reason: 'sort-members must emit constructors first',
        );

        // The bug: sort-constructors-first used to lift the constructors above the
        // fields, undoing sort-members. On the already-sorted output it must now
        // be a byte-for-byte no-op.
        final lifted = await invokeCli(
          project,
          args: onlyFeatureArgs('sort_constructors_first'),
        );
        expect(lifted.exitCode, 0, reason: lifted.stderr);
        expect(
          lifted.read('lib/a.dart'),
          afterMembers,
          reason:
              'sort-constructors-first changed sort-members output: the two '
              'passes disagree and oscillate',
        );
      },
    );

    test('the two passes reach the same fixed point in either order', () async {
      final project = createProject(files: {'lib/a.dart': scrambled});

      // constructors-first, then a full member sort, then constructors-first
      // again. The last step must be a no-op: the file has settled.
      final first = await invokeCli(
        project,
        args: onlyFeatureArgs('sort_constructors_first'),
      );
      expect(first.exitCode, 0, reason: first.stderr);

      final second = await invokeCli(
        project,
        args: onlyFeatureArgs('sort_members'),
      );
      expect(second.exitCode, 0, reason: second.stderr);
      final settled = second.read('lib/a.dart');

      final third = await invokeCli(
        project,
        args: onlyFeatureArgs('sort_constructors_first'),
      );
      expect(third.exitCode, 0, reason: third.stderr);
      expect(
        third.read('lib/a.dart'),
        settled,
        reason: 'the passes never reach a fixed point; they keep reordering',
      );
    });
  });

  group('after a full run, every region-rewriting pass is a no-op', () {
    // primary-constructors is disabled here on purpose: it promotes an eligible
    // class to primary-constructor form, which needs a language experiment the
    // fixture SDK does not enable, and it is orthogonal to the member/import
    // ordering this suite guards. sort-members is switched on explicitly because
    // it is off by default and its ordering is exactly what this suite checks.
    // Every other pass runs.
    final baseArgs = [
      ...withoutFeatureArgs('primary_constructors'),
      ...enableFeatureArgs('sort_members'),
    ];

    // dart:math is unused (organize-imports prunes it) and the two imports are
    // out of order; the class members are scrambled and the class has two
    // constructors so it is never promoted to primary-constructor form.
    const source = '''
import 'dart:math';
import 'dart:async';

class Store {
  void add(int x) {}

  final List<int> items;
  static int version = 1;

  Store(this.items);

  int get size => items.length;

  Store.empty() : this(const []);

  Future<void> flush() async {}
}
''';

    const file = 'lib/store.dart';
    late String modernized;

    setUpAll(() async {
      final project = createProject(files: {file: source});
      final run = await invokeCli(project, args: baseArgs);
      expect(run.exitCode, 0, reason: run.stderr);
      modernized = run.read(file);
    });

    test('the full run actually modernized the file', () {
      expect(
        modernized,
        isNot(source),
        reason:
            'the baseline must be transformed for the no-op checks to mean '
            'anything',
      );
      // Constructors first, imports pruned: the canonical, settled shape.
      expect(modernized, isNot(contains("import 'dart:math';")));
      expect(
        modernized,
        stringContainsInOrder([
          'Store(this.items);',
          'Store.empty()',
          'final List<int> items',
          'int get size',
        ]),
      );
    });

    // Each pass that rewrites whole regions on disk (imports and members) must
    // leave the already-modernized file untouched. If any one of them changes
    // it, that pass disagrees with the settled result the full run produced.
    for (final pass in const [
      'organize_imports',
      'sort_members',
      'sort_constructors_first',
    ]) {
      test('running only $pass changes nothing', () async {
        final project = createProject(files: {file: modernized});
        final rerun = await invokeCli(project, args: onlyFeatureArgs(pass));
        expect(rerun.exitCode, 0, reason: rerun.stderr);
        expect(
          rerun.read(file),
          modernized,
          reason:
              'running only $pass changed a fully-modernized file; it undoes '
              'work another pass did',
        );
      });
    }
  });
}
