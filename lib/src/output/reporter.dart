/// Terminal output layer for dart_modernize.
///
/// This is the single place that knows about ANSI styling. All other code
/// calls methods on [Reporter] and never writes to stdout/stderr directly.
library;

import 'dart:io';

import 'package:tint/tint.dart';

/// Resolves whether ANSI color should be used.
///
/// Priority (highest first):
///   1. [colorFlag] == false  (--no-color)
///   2. NO_COLOR environment variable present
///   3. [colorFlag] == true   (--color)
///   4. stdout.hasTerminal    (auto-detect)
bool resolveColor({required bool? colorFlag}) {
  if (colorFlag == false) return false;
  if (Platform.environment.containsKey('NO_COLOR')) return false;
  if (colorFlag == true) return true;
  return stdout.supportsAnsiEscapes;
}

/// The single output layer for dart_modernize.
///
/// All stdout/stderr writes go through here. When [color] is false, no ANSI
/// codes are emitted and the text content is identical to plain output.
///
/// Pass custom [out]/[err] sinks in tests to capture output without touching
/// real stdout/stderr.
final class Reporter {
  Reporter({
    required this.color,
    required this.verbose,
    StringSink? out,
    StringSink? err,
  }) : _outSink = out ?? stdout,
       _errSink = err ?? stderr;
  final bool color;
  final bool verbose;
  final StringSink _outSink;

  final StringSink _errSink;

  /// One-line summary for a `--check` run: how many files would change.
  ///
  /// No diff is printed (pair `--check` with `--dry-run` for that). When
  /// [changed] is greater than zero the run then exits non-zero.
  void checkSummary({required int scanned, required int changed}) {
    _out(_rule());
    if (changed == 0) {
      _out(
        '  ${_bold('✓')} Already modern -- $scanned file(s) scanned, '
        'nothing to change.',
      );
    } else {
      final noun = changed == 1 ? 'file' : 'files';
      _out(
        '  ${_red('✗')} $changed of $scanned $noun would change. '
        'Run without --check to apply.',
      );
    }
    _out(_rule());
  }

  /// Lists the files `dart fix` would change in a preview run.
  ///
  /// `dart fix` only works on files on disk, so a preview cannot show its
  /// edits as a diff; it names the files instead.
  void dartFixPreview(List<String> files) {
    if (files.isEmpty) return;
    final noun = files.length == 1 ? 'file' : 'files';
    _out('dart fix would also change ${files.length} $noun:');
    for (final file in files) {
      _out('  ${_bold(file)}');
    }
  }

  /// Reports changes undone in memory because they introduced an error, keyed
  /// by project-relative path, with the passes held back in each file.
  void heldBack(Map<String, Set<String>> passesByFile) {
    if (passesByFile.isEmpty) return;
    final noun = passesByFile.length == 1 ? 'file' : 'files';
    _out(
      '${_yellow('!')} Held back changes in ${passesByFile.length} $noun '
      'that would have introduced an error:',
    );
    for (final MapEntry(:key, :value) in passesByFile.entries) {
      _out('  ${_bold(key)}  ${_dim('[${value.join(', ')}]')}');
    }
  }

  /// Reports diagnostics that are not errors but appeared during the run, so
  /// a project that runs `dart analyze --fatal-infos` in CI knows before it
  /// pushes. Nothing is undone for them.
  void newDiagnostics(Map<String, List<String>> byFile) {
    if (byFile.isEmpty) return;
    final count = byFile.values.fold(0, (sum, list) => sum + list.length);
    final noun = count == 1 ? 'warning or info' : 'warnings or infos';
    _out(
      '${_yellow('!')} $count new $noun appeared (changes kept; run dart '
      'analyze to review):',
    );
    for (final MapEntry(:key, :value) in byFile.entries) {
      _out('  ${_bold(key)}');
      for (final message in value) {
        _out('    ${_yellow('-')} $message');
      }
    }
  }

  /// No interrupted run left files to put back.
  void nothingToRestore() => _out('Nothing to restore.');

  /// Reports the files `--restore` put back.
  void restored(List<String> files) {
    final noun = files.length == 1 ? 'file' : 'files';
    _out('${_green('✓')} Restored ${files.length} $noun.');
    for (final file in files) {
      _out('  ${_bold(file)}');
    }
  }

  /// The SDK constraint `--upgrade-sdk` raised, from [from] to [to].
  void sdkUpgraded(String from, String to) =>
      _out('${_green('✓')} Raised the SDK constraint from "$from" to "$to".');

  /// Reports files left untouched because their library could not be
  /// resolved (the analyzer overflowed the stack).
  void unresolvable(List<String> files) {
    if (files.isEmpty) return;
    final noun = files.length == 1 ? 'file' : 'files';
    _out(
      '${_yellow('!')} Skipped ${files.length} $noun the analyzer could not '
      'resolve (stack overflow on a deeply nested expression):',
    );
    for (final file in files) {
      _out('  ${_bold(file)}');
    }
  }

  /// Prints [text] only in `--verbose` mode.
  void verboseLine(String text) {
    if (verbose) _out(_dim(text));
  }

  /// Prints the end-of-run banner: how many files changed and how many each
  /// transformation touched, in canonical pass order.
  void completionSummary({
    required int scanned,
    required int changed,
    required Map<String, int> passCounts,
  }) {
    _out(_rule());
    if (changed == 0) {
      _out(
        '  ${_bold('✓')} Already modern -- $scanned file(s) scanned, '
        'nothing to change.',
      );
      _out(_rule());
      return;
    }
    _out(
      '  ${_green('✓')} ${_bold('Modernized $changed of $scanned file(s).')}',
    );
    if (passCounts.isNotEmpty) {
      _out('');
      final nameWidth = passCounts.keys
          .map((k) => k.length)
          .reduce((a, b) => a > b ? a : b);
      for (final MapEntry(:value, :key) in passCounts.entries) {
        final noun = value == 1 ? 'file' : 'files';
        _out(
          '  ${key.padRight(nameWidth)}  '
          '${_green(value.toString().padLeft(4))} $noun',
        );
      }
    }
    _out(_rule());
  }

  void dryRunSummary({
    required int scanned,
    required int changed,
    required int added,
    required int removed,
    required Map<String, int> passCounts,
  }) {
    _out(_rule());
    _out(
      '  ${_bold('dry run')} -- $changed of $scanned file(s) would change, '
      'nothing written',
    );
    if (added > 0 || removed > 0) {
      _out('  ${_green('+$added')} additions, ${_red('-$removed')} removals');
    }
    if (passCounts.isNotEmpty) {
      _out('');
      final nameWidth = passCounts.keys
          .map((k) => k.length)
          .reduce((a, b) => a > b ? a : b);
      for (final MapEntry(:key, :value) in passCounts.entries) {
        _out('  ${key.padRight(nameWidth)}  $value file(s)');
      }
    }
    _out(_rule());
  }

  void error(String message) => _err(_errorText('Error: $message'));

  void errorHint(String hint) => _err(_dim(hint));

  void finalizing() => _out(_dim('Finalizing…'));
  void finalizingStep(String label) => _out(_dim('  $label…'));

  void help(String usage) {
    _out('${_bold('Usage:')} dart_modernize [options] [path]\n');
    _out(usage);
  }

  void nothingToDo() {
    _out(_rule());
    _out('  No transformations enabled; nothing to do.');
    _out(_rule());
  }

  void plain(String text) => _out(text);

  /// Renders a unified diff for one changed file.
  ///
  /// [rel] is the project-relative path. [passes] lists which structural
  /// passes contributed edits. [added]/[removed] are the line counts parsed
  /// from [diffText]. [diffText] is the raw output of [unifiedDiff].
  void renderDiff(
    String rel,
    List<String> passes,
    int added,
    int removed,
    String diffText,
  ) {
    _out(_fileHeader(rel, passes, added, removed));
    _writeDiff(diffText);
    _outSink.writeln();
  }

  void resolving() => _out(_dim('Resolving…'));

  void unexpectedError(Object e) => _err(_errorText('Unexpected error: $e'));

  void validated() => _out(_bold('✓ Project validated.'));

  /// Reports files that were reverted because re-analysis found a new error.
  ///
  /// [reverted] maps each project-relative path to the new error messages
  /// behind its revert, and [passes] to the passes that had edited it. Printed
  /// to stderr after the completion summary; the run then exits with code 2.
  /// The hint names the `--no-<pass>` switches that would skip those passes,
  /// never `--no-verify`, which would keep code that does not compile.
  void verificationReverted(
    Map<String, List<String>> reverted, {
    Map<String, Set<String>> passes = const {},
  }) {
    final noun = reverted.length == 1 ? 'file' : 'files';
    _err(
      _errorText(
        'Reverted ${reverted.length} $noun that stopped compiling after '
        'modernization:',
      ),
    );
    for (final MapEntry(:key, :value) in reverted.entries) {
      final names = passes[key] ?? const <String>{};
      final label = names.isEmpty ? '' : '  ${_dim('[${names.join(', ')}]')}';
      _err('  ${_bold(key)}$label');
      for (final message in value) {
        _err('    ${_red('-')} $message');
      }
    }
    final skip = {for (final names in passes.values) ...names};
    _err(
      _dim(
        'Every other change was kept. '
        '${skip.isEmpty ? '' : 'To leave these files alone next time, re-run '
                  'with ${skip.map((n) => '--no-$n').join(' ')}.'}',
      ),
    );
  }

  /// Reports new errors the run could not trace back to a file it changed,
  /// keyed by project-relative path.
  void unexplainedErrors(Map<String, List<String>> byFile) {
    if (byFile.isEmpty) return;
    _err(
      _errorText(
        'These errors appeared and could not be traced to a single change:',
      ),
    );
    for (final MapEntry(:key, :value) in byFile.entries) {
      _err('  ${_bold(key)}');
      for (final message in value) {
        _err('    ${_red('-')} $message');
      }
    }
  }

  void verifying() => _out(_dim('Verifying…'));

  void version(String v) => _out('${_bold('dart_modernize')} ${_dim(v)}');

  String _bold(String s) => color ? s.bold() : s;

  String _cyan(String s) => color ? s.cyan() : s;

  String _diffLine(String line) {
    if (line.startsWith('---') || line.startsWith('+++')) return _bold(line);
    if (line.startsWith('@@')) return _cyan(line);
    if (line.startsWith('+')) return _green(line);
    if (line.startsWith('-')) return _red(line);
    return line;
  }

  String _dim(String s) => color ? s.dim() : s;

  void _err(String s) => _errSink.writeln(s);
  String _errorText(String s) => color ? s.bold().red() : s;
  String _fileHeader(String rel, List<String> passes, int added, int removed) {
    final counts = (added > 0 || removed > 0)
        ? '  ${_green('+$added')} ${_red('-$removed')}'
        : '';
    final passLabel = passes.isEmpty
        ? ''
        : '  ${_dim('[${passes.join(', ')}]')}';
    return '${_bold(rel)}$counts$passLabel';
  }

  String _green(String s) => color ? s.green() : s;
  void _out(String s) => _outSink.writeln(s);
  String _red(String s) => color ? s.red() : s;
  String _yellow(String s) => color ? s.yellow() : s;

  String _rule() {
    const line = '────────────────────────────────────────────────────────';
    return _dim(line);
  }

  void _writeDiff(String diffText) {
    // Remove trailing newline before splitting so writeln produces the same
    // byte sequence as the original stdout.write(diffText) + stdout.writeln().
    final trimmed = diffText.endsWith('\n')
        ? diffText.substring(0, diffText.length - 1)
        : diffText;
    for (final line in trimmed.split('\n')) {
      _outSink.writeln(_diffLine(line));
    }
  }
}
