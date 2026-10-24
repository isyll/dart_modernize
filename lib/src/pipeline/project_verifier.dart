import 'dart:io';

import 'package:path/path.dart' as p;

import '../analysis/sdk_analysis.dart';
import '../engine/import_graph.dart';

/// Checks the written result of a run and undoes the changes behind every new
/// error.
///
/// A new error in a changed file reverts that file. A new error in a file the
/// run did not change (a caller of a constructor whose signature moved)
/// reverts the changed files it depends on. Each revert can expose another
/// error, so the check repeats until the project is clean. When an error
/// cannot be traced to a change, or [maxRounds] go by, every change still in
/// place is reverted too: a run never leaves an error it caused.
///
/// [analyze] runs `dart analyze` over the project in the pipeline; it is a
/// parameter so the logic can be exercised without the SDK.
final class ProjectVerifier({
  required final Future<Map<String, List<SdkDiagnostic>>> Function() analyze,
  required final ImportGraph graph,
  required final String projectPath,
  final int maxRounds = 4,
}) {
  /// Compares the project against [baseline] (diagnostics by canonical path,
  /// taken before anything was written) and reverts what broke.
  ///
  /// [changed] are the files the run wrote, [originals] their content before
  /// the run, and [files] every Dart file of the project.
  Future<VerifyOutcome> verify({
    required Map<String, List<SdkDiagnostic>> baseline,
    required Set<String> changed,
    required Map<String, String> originals,
    required Iterable<String> files,
  }) async {
    if (changed.isEmpty) return const VerifyOutcome();

    final byCanonical = {
      for (final path in {...files, ...changed}) p.canonicalize(path): path,
    };
    final reverted = <String, List<String>>{};
    void revert(String path, List<String> reasons) {
      final original = originals[path];
      if (original == null) return;
      // The analyzer's view of the file (a leading BOM is stripped); the
      // pipeline's shape restore puts the original line ending and BOM back.
      File(path).writeAsStringSync(original);
      (reverted[path] ??= []).addAll(reasons);
    }

    var current = await analyze();
    var newErrors = _newErrors(baseline, current);
    for (var round = 0; newErrors.isNotEmpty && round < maxRounds; round++) {
      final active = changed.difference(reverted.keys.toSet());
      final culprits = <String, List<String>>{};
      var traced = true;
      for (final MapEntry(key: canonical, value: errors) in newErrors.entries) {
        final path = byCanonical[canonical] ?? canonical;
        if (active.contains(path)) {
          (culprits[path] ??= []).addAll(errors);
          continue;
        }
        final suspects = graph.suspectsFor(path, active);
        if (suspects.isEmpty) traced = false;
        for (final suspect in suspects) {
          (culprits[suspect] ??= []).addAll([
            for (final error in errors) 'in ${_relative(path)}: $error',
          ]);
        }
      }
      if (!traced || culprits.isEmpty) break;
      culprits.forEach(revert);
      current = await analyze();
      newErrors = _newErrors(baseline, current);
    }

    var unexplained = const <String, List<String>>{};
    if (newErrors.isNotEmpty) {
      // Some error could not be pinned on one change: take back the rest of
      // the run, and report whatever is still there, which the run did not
      // cause.
      final remaining = changed.difference(reverted.keys.toSet());
      if (remaining.isNotEmpty) {
        for (final path in remaining) {
          revert(path, const [_untraced]);
        }
        current = await analyze();
        newErrors = _newErrors(baseline, current);
      }
      unexplained = {
        for (final MapEntry(:key, :value) in newErrors.entries)
          _relative(byCanonical[key] ?? key): value,
      };
    }

    // Warnings and infos never block a run, but a project that runs dart
    // analyze --fatal-infos in CI wants to hear about new ones.
    final revertedCanonical = {
      for (final path in reverted.keys) p.canonicalize(path),
    };
    final newDiagnostics = <String, List<String>>{};
    for (final MapEntry(key: canonical, value: diagnostics)
        in current.entries) {
      if (revertedCanonical.contains(canonical)) continue;
      final added = newSignatures(
        [
          for (final d in baseline[canonical] ?? const <SdkDiagnostic>[])
            if (!d.isError) d.signature,
        ],
        [
          for (final d in diagnostics)
            if (!d.isError) d.signature,
        ],
      );
      if (added.isNotEmpty) {
        newDiagnostics[_relative(byCanonical[canonical] ?? canonical)] = added;
      }
    }

    return .new(
      reverted: reverted,
      unexplained: unexplained,
      newDiagnostics: newDiagnostics,
    );
  }

  static const _untraced =
      'reverted with the rest of the run: a new error could not be traced to '
      'one change';

  String _relative(String path) =>
      p.relative(path, from: projectPath).replaceAll(r'\', '/');

  /// The new error signatures per canonical path between [baseline] and
  /// [current].
  static Map<String, List<String>> _newErrors(
    Map<String, List<SdkDiagnostic>> baseline,
    Map<String, List<SdkDiagnostic>> current,
  ) {
    final result = <String, List<String>>{};
    for (final MapEntry(:key, :value) in current.entries) {
      final added = newSignatures(
        [
          for (final d in baseline[key] ?? const <SdkDiagnostic>[])
            if (d.isError) d.signature,
        ],
        [
          for (final d in value)
            if (d.isError) d.signature,
        ],
      );
      if (added.isNotEmpty) result[key] = added;
    }
    return result;
  }
}

/// Outcome of [ProjectVerifier.verify].
final class const VerifyOutcome({
  /// Reverted files (absolute paths) and the errors behind each revert.
  final Map<String, List<String>> reverted = const {},

  /// New errors still there after every change was taken back, by
  /// project-relative path. The run did not cause them.
  final Map<String, List<String>> unexplained = const {},

  /// New warnings and infos in the files the run kept, by project-relative
  /// path.
  final Map<String, List<String>> newDiagnostics = const {},
});
