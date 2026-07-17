/// Behavioural spec for issue #14: the tool refuses to run on a Git work tree
/// with uncommitted changes unless `--allow-dirty` is passed, so its edits land
/// in their own reviewable diff.
library;

import 'dart:io';

import 'package:test/test.dart';

import '../support/cli_harness.dart';
import '../support/triggers.dart';

/// Runs a git command in [dir], with a throwaway identity so `commit` works in
/// a fresh repo, and fails loudly if git itself errors.
void _git(Directory dir, List<String> args) {
  final result = Process.runSync('git', [
    '-c',
    'user.email=test@example.com',
    '-c',
    'user.name=Test',
    ...args,
  ], workingDirectory: dir.path);
  if (result.exitCode != 0) {
    throw StateError('git ${args.join(' ')} failed: ${result.stderr}');
  }
}

/// A fresh repo whose tracked `lib/a.dart` has a staged, uncommitted change.
Directory _dirtyRepo() {
  final project = createProject(files: {'lib/a.dart': expressionBodiesTrigger});
  _git(project, const ['init', '-q']);
  // A staged addition is an uncommitted change to a tracked file.
  _git(project, const ['add', 'lib/a.dart']);
  return project;
}

void main() {
  group('dirty Git tree guard', () {
    test('refuses and writes nothing when the tree is dirty', () async {
      final project = _dirtyRepo();

      final result = await invokeCli(
        project,
        args: onlyFeatureArgs('expression_bodies'),
      );

      expect(result.exitCode, isNonZero, reason: 'must refuse on a dirty tree');
      expect(
        result.stderr,
        contains('--allow-dirty'),
        reason: 'the message must point at the override',
      );
      expect(
        result.read('lib/a.dart'),
        expressionBodiesTrigger,
        reason: 'nothing may be written when the run is refused',
      );
    });

    test('--allow-dirty runs anyway', () async {
      final project = _dirtyRepo();

      final result = await invokeCli(
        project,
        args: ['--allow-dirty', ...onlyFeatureArgs('expression_bodies')],
      );

      expect(result.exitCode, 0, reason: result.stderr);
      expect(
        result.read('lib/a.dart'),
        contains('=>'),
        reason: '--allow-dirty lets the run proceed',
      );
    });

    test(
      '--dry-run is not blocked by a dirty tree and writes nothing',
      () async {
        final project = _dirtyRepo();

        final result = await invokeCli(
          project,
          args: ['--dry-run', ...onlyFeatureArgs('expression_bodies')],
        );

        expect(result.exitCode, 0, reason: result.stderr);
        expect(
          result.read('lib/a.dart'),
          expressionBodiesTrigger,
          reason: 'a dry run previews without writing, so dirtiness is moot',
        );
      },
    );

    test('a clean committed tree runs normally', () async {
      final project = createProject(
        files: {'lib/a.dart': expressionBodiesTrigger},
      );
      _git(project, const ['init', '-q']);
      _git(project, const ['add', '-A']);
      _git(project, const ['commit', '-q', '-m', 'init']);

      final result = await invokeCli(
        project,
        args: onlyFeatureArgs('expression_bodies'),
      );

      expect(result.exitCode, 0, reason: result.stderr);
      expect(result.read('lib/a.dart'), contains('=>'));
    });

    test('a project outside any Git repo runs normally', () async {
      final result = await runCli(
        files: {'lib/a.dart': expressionBodiesTrigger},
        args: onlyFeatureArgs('expression_bodies'),
      );

      expect(result.exitCode, 0, reason: result.stderr);
      expect(
        result.read('lib/a.dart'),
        contains('=>'),
        reason: 'the guard is skipped when the target is not in a repo',
      );
    });
  });
}
