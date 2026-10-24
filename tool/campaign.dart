/// Runs dart_modernize over a copy of a real project and checks that nothing
/// breaks.
///
/// ```sh
/// dart run tool/campaign.dart --name bloc \
///   --git https://github.com/felangel/bloc.git --ref <sha> \
///   --sub examples/flutter_todos [--tests] [--no-second-run]
/// dart run tool/campaign.dart --name mine --local ../my_app --tests
/// ```
///
/// The source project is never touched: a local one is copied, a remote one is
/// cloned into `.dart_tool/campaign/<name>`. The project's SDK constraint is
/// raised to the tool's floor when it allows less, `pub get` runs, and a
/// baseline commit is made. Then the tool runs once, and the run fails when:
///
///   * the tool exits non-zero (2 means it had to revert files);
///   * `dart analyze` reports an error the baseline did not have;
///   * with `--tests`, the project's tests pass before and fail after;
///   * unless `--no-second-run`, a second run still changes something.
///
/// A summary goes to stdout and to `.dart_tool/campaign/<name>.json`; the exit
/// code is 1 on any failure, so a CI job can gate on it.
library;

import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('name', mandatory: true, help: 'Folder name for the copy.')
    ..addOption('local', help: 'A project directory to copy.')
    ..addOption('git', help: 'A repository URL to clone.')
    ..addOption('ref', help: 'The commit, tag, or branch to check out.')
    ..addOption('sub', defaultsTo: '', help: 'The package inside the repo.')
    ..addFlag('tests', help: "Run the project's tests before and after.")
    ..addFlag('second-run', defaultsTo: true, help: 'Check idempotence.');
  final ArgResults args;
  try {
    args = parser.parse(arguments);
  } on FormatException catch (e) {
    stderr.writeln('${e.message}\n\n${parser.usage}');
    exit(64);
  }
  final local = args['local'] as String?;
  final git = args['git'] as String?;
  if ((local == null) == (git == null)) {
    stderr.writeln('Pass exactly one of --local or --git.');
    exit(64);
  }

  final tool = Directory.current.path;
  final name = args['name'] as String;
  final work = p.join(tool, '.dart_tool', 'campaign', name);
  final report = <String, Object?>{'name': name, 'source': local ?? git};
  final failures = <String>[];

  if (Directory(work).existsSync()) Directory(work).deleteSync(recursive: true);
  if (local != null) {
    _copy(Directory(local), Directory(work));
    await _git(['init', '-q'], work);
  } else {
    await _run('git', ['clone', '-q', git!, work], tool);
    final ref = args['ref'] as String?;
    if (ref != null) await _git(['checkout', '-q', ref], work);
  }

  final project = p.join(work, args['sub'] as String);
  report['raisedSdkFrom'] = _raiseSdk(p.join(project, 'pubspec.yaml'));
  final pubspec = File(p.join(project, 'pubspec.yaml')).readAsStringSync();
  final flutter = RegExp(r'sdk:\s*flutter').hasMatch(pubspec);
  final runner = flutter ? 'flutter' : Platform.resolvedExecutable;
  await _run(runner, ['pub', 'get'], project);
  await _git(['add', '-A'], work);
  await _git(['commit', '-qm', 'baseline', '--allow-empty'], work);

  final before = await _errors(project);
  final testsBefore = args['tests'] as bool
      ? await _tests(runner, project)
      : null;

  final first = await _modernize(tool, project);
  report['run'] = first;
  if (first['exit'] != 0) failures.add('run exited with ${first['exit']}');

  final after = await _errors(project);
  final introduced = [
    for (final error in after)
      if (!before.contains(error)) error,
  ];
  report['newErrors'] = introduced;
  if (introduced.isNotEmpty) failures.add('${introduced.length} new error(s)');

  if (testsBefore != null) {
    final testsAfter = await _tests(runner, project);
    report['tests'] = {'before': testsBefore, 'after': testsAfter};
    if (testsBefore && !testsAfter) failures.add('tests went red');
  }

  if (args['second-run'] as bool) {
    await _git(['add', '-A'], work);
    await _git(['commit', '-qm', 'run 1', '--allow-empty'], work);
    final second = await _modernize(tool, project);
    final diff = await _run('git', [
      'diff',
      '--ignore-cr-at-eol',
      '--stat',
    ], work);
    report['secondRun'] = {...second, 'diff': diff.trim()};
    if (diff.trim().isNotEmpty) failures.add('second run changed files');
  }

  report['failures'] = failures;
  final json = const JsonEncoder.withIndent('  ').convert(report);
  File(p.join(tool, '.dart_tool', 'campaign', '$name.json'))
      .writeAsStringSync(json);
  stdout.writeln(json);
  if (failures.isNotEmpty) exit(1);
}

void _copy(Directory from, Directory to) {
  const skip = {'build', '.dart_tool', '.git', 'Pods', '.symlinks', '.idea'};
  to.createSync(recursive: true);
  for (final entity in from.listSync(followLinks: false)) {
    final name = p.basename(entity.path);
    if (skip.contains(name)) continue;
    final target = p.join(to.path, name);
    if (entity is Directory) {
      _copy(entity, Directory(target));
    } else if (entity is File) {
      entity.copySync(target);
    }
  }
}

/// The `code: file` keys of every error `dart analyze` reports.
Future<Set<String>> _errors(String project) async {
  final result = await Process.run(Platform.resolvedExecutable, [
    'analyze',
    '--format=machine',
    '.',
  ], workingDirectory: project);
  return {
    for (final line in const LineSplitter().convert('${result.stdout}'))
      if (line.split('|') case ['ERROR', _, final code, final file, ...])
        '$code: ${p.relative(file, from: project)}',
  };
}

Future<void> _git(List<String> args, String cwd) => _run('git', [
  '-c',
  'core.longpaths=true',
  '-c',
  'core.autocrlf=false',
  '-c',
  'user.email=campaign@dart-modernize',
  '-c',
  'user.name=campaign',
  ...args,
], cwd);

Future<Map<String, Object?>> _modernize(String tool, String project) async {
  final watch = Stopwatch()..start();
  final result = await Process.run(Platform.resolvedExecutable, [
    'run',
    p.join(tool, 'bin', 'dart_modernize.dart'),
    '--no-color',
    '--verbose',
    project,
  ], workingDirectory: tool);
  stdout
    ..write(result.stdout)
    ..write(result.stderr);
  return {'exit': result.exitCode, 'seconds': watch.elapsed.inSeconds};
}

/// Raises the SDK constraint to ^3.13.0 when it allows less, and returns the
/// old one, or null when it already starts there.
String? _raiseSdk(String pubspecPath) {
  final file = File(pubspecPath);
  final text = file.readAsStringSync();
  final match = RegExp(
    r'''^(\s+sdk:\s*)(['"]?)([^'"\n]+)\2\s*$''',
    multiLine: true,
  ).firstMatch(text);
  if (match == null) return null;
  final old = match.group(3)!.trim();
  final minor = RegExp(r'3\.(\d+)').firstMatch(old);
  if (minor != null && int.parse(minor.group(1)!) >= 13) return null;
  file.writeAsStringSync(
    text.replaceRange(match.start, match.end, '${match.group(1)}^3.13.0'),
  );
  return old;
}

/// Runs [executable] and returns its stdout, failing the campaign when it
/// exits non-zero.
Future<String> _run(String executable, List<String> args, String cwd) async {
  final result = await Process.run(
    executable,
    args,
    workingDirectory: cwd,
    runInShell: Platform.isWindows,
  );
  if (result.exitCode != 0) {
    stderr.writeln('$executable ${args.join(' ')} failed:\n${result.stderr}');
    exit(1);
  }
  return '${result.stdout}';
}

/// Whether the project's tests pass.
Future<bool> _tests(String runner, String project) async {
  if (!Directory(p.join(project, 'test')).existsSync()) return true;
  final result = await Process.run(
    runner,
    ['test', '--reporter=compact'],
    workingDirectory: project,
    runInShell: Platform.isWindows,
  );
  return result.exitCode == 0;
}
