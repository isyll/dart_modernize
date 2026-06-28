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
  final bool color;
  final bool verbose;
  final StringSink _outSink;
  final StringSink _errSink;

  Reporter({
    required this.color,
    required this.verbose,
    StringSink? out,
    StringSink? err,
  }) : _outSink = out ?? stdout,
       _errSink = err ?? stderr;

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
      for (final entry in passCounts.entries) {
        final noun = entry.value == 1 ? 'file' : 'files';
        _out(
          '  ${entry.key.padRight(nameWidth)}  '
          '${_green(entry.value.toString().padLeft(4))} $noun',
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
      for (final entry in passCounts.entries) {
        _out('  ${entry.key.padRight(nameWidth)}  ${entry.value} file(s)');
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
