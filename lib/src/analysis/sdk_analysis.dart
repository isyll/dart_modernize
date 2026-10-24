import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'dart_sdk.dart';

/// One diagnostic reported by `dart analyze`.
final class const SdkDiagnostic({
  required final String severity,
  required final String code,
  required final String message,
}) {
  bool get isError => severity == 'ERROR';

  /// `code: message`, without the position, so an edit that only shifts an
  /// unrelated diagnostic is not mistaken for a new one.
  String get signature => '$code: $message';
}

/// Runs `dart analyze --format=machine` over [projectPath] and returns every
/// diagnostic, keyed by canonicalized file path.
///
/// `dart analyze` is used, not the in-process analyzer, so the verdict matches
/// exactly what the user's SDK reports. It exits non-zero whenever it finds
/// issues, so its exit code is ignored and stdout is parsed instead.
Future<Map<String, List<SdkDiagnostic>>> analyzeWithSdk(
  DartSdk sdk,
  String projectPath,
) => SdkAnalysis.start(sdk, projectPath).then((run) => run.result);

/// A `dart analyze --format=machine` run in progress.
///
/// The pipeline starts the pre-edit baseline before the transform stages and
/// collects it after, so the two overlap; [cancel] stops it when the run turns
/// out to change nothing.
final class SdkAnalysis {
  SdkAnalysis._(this._process, this.result);

  static Future<SdkAnalysis> start(DartSdk sdk, String projectPath) async {
    final process = await Process.start(sdk.dartExecutable, [
      'analyze',
      '--format=machine',
      projectPath,
    ], workingDirectory: projectPath);
    final stdout = process.stdout.transform(systemEncoding.decoder).join();
    unawaited(process.stderr.drain<void>());
    final result = Future.wait([stdout, process.exitCode])
        .then((values) => parseMachineDiagnostics(values.first as String));
    return ._(process, result);
  }

  final Process _process;

  /// Every diagnostic, keyed by canonicalized file path.
  final Future<Map<String, List<SdkDiagnostic>>> result;

  /// Stops the analysis; [result] is then never awaited.
  void cancel() {
    _process.kill();
    unawaited(result.then((_) {}, onError: (Object _) {}));
  }
}

/// Parses `dart analyze --format=machine` output into diagnostics keyed by
/// canonicalized file path.
Map<String, List<SdkDiagnostic>> parseMachineDiagnostics(String output) {
  final diagnostics = <String, List<SdkDiagnostic>>{};
  for (final line in const LineSplitter().convert(output)) {
    // SEVERITY|TYPE|CODE|FILE|LINE|COLUMN|LENGTH|MESSAGE, with \ | and
    // newlines backslash-escaped inside fields.
    final parts = line.split('|');
    if (parts.length < 8) continue;
    final severity = parts[0];
    if (severity != 'ERROR' && severity != 'WARNING' && severity != 'INFO') {
      continue;
    }
    final file = p.canonicalize(_unescapeMachine(parts[3]));
    (diagnostics[file] ??= []).add(
      .new(
        severity: severity,
        code: parts[2],
        message: _unescapeMachine(parts.sublist(7).join('|')),
      ),
    );
  }
  return diagnostics;
}

/// The signatures in [after] not present in [before].
///
/// Matched as a multiset, so a pre-existing entry is consumed once and only
/// genuinely new ones are returned.
List<String> newSignatures(List<String> before, List<String> after) {
  final remaining = [...before];
  final added = <String>[];
  for (final signature in after) {
    final index = remaining.indexOf(signature);
    if (index >= 0) {
      remaining.removeAt(index);
    } else {
      added.add(signature);
    }
  }
  return added;
}

/// Reverses `dart analyze --format=machine` field escaping, where a backslash
/// escapes the next character and an escaped `n` is a newline.
String _unescapeMachine(String field) {
  final buffer = StringBuffer();
  for (var i = 0; i < field.length; i++) {
    if (field[i] == '\\' && i + 1 < field.length) {
      final next = field[++i];
      buffer.write(next == 'n' ? '\n' : next);
    } else {
      buffer.write(field[i]);
    }
  }
  return buffer.toString();
}
