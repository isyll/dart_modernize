import 'dart:io';

import 'package:path/path.dart' as p;

import '../modernize_exception.dart';

/// The Dart SDK the tool analyzes against and runs `dart` subcommands with.
///
/// Under the Dart VM (`dart run`, `dart pub global activate`) the running
/// executable is the SDK's own `dart`, so both come from it. A compiled
/// executable is the tool itself: launching `Platform.resolvedExecutable
/// analyze` would start the tool again, and the analyzer cannot infer the SDK
/// from the executable's location. In that case the SDK is found through
/// `DART_SDK`, then `FLUTTER_ROOT`, then the `dart` on the `PATH`.
final class const DartSdk({required final String path}) {
  /// Resolves the SDK for this process, or throws when none can be found.
  factory resolve() {
    final running = Platform.resolvedExecutable;
    if (_isDartBinary(running)) {
      final root = p.dirname(p.dirname(running));
      if (_isSdkRoot(root)) return DartSdk(path: root);
    }

    final env = Platform.environment;
    final candidates = [
      ?env['DART_SDK'],
      if (env['FLUTTER_ROOT'] case final flutter?)
        p.join(flutter, 'bin', 'cache', 'dart-sdk'),
      ..._sdksOnPath(env['PATH'] ?? ''),
    ];
    for (final candidate in candidates) {
      final root = p.normalize(p.absolute(candidate));
      if (_isSdkRoot(root)) return DartSdk(path: root);
    }
    throw const ModernizeException(
      'Could not find the Dart SDK. Set DART_SDK to its root directory, or put '
      'dart on the PATH.',
    );
  }

  /// The `dart` executable inside [path].
  String get dartExecutable =>
      p.join(path, 'bin', Platform.isWindows ? 'dart.exe' : 'dart');

  /// SDK roots implied by each `dart` found on [pathVariable]: the directory
  /// above `bin/`, or Flutter's bundled SDK when `dart` is Flutter's wrapper.
  static Iterable<String> _sdksOnPath(String pathVariable) sync* {
    final separator = Platform.isWindows ? ';' : ':';
    final names = Platform.isWindows
        ? const ['dart.exe', 'dart.bat', 'dart']
        : const ['dart'];
    for (final dir in pathVariable.split(separator)) {
      if (dir.isEmpty) continue;
      for (final name in names) {
        final file = File(p.join(dir, name));
        if (!file.existsSync()) continue;
        final binDir = p.dirname(file.resolveSymbolicLinksSync());
        final root = p.dirname(binDir);
        yield p.join(root, 'bin', 'cache', 'dart-sdk');
        yield root;
      }
    }
  }

  static bool _isDartBinary(String executable) {
    final name = p.basenameWithoutExtension(executable).toLowerCase();
    return name == 'dart' || name == 'dartvm' || name == 'dartaotruntime';
  }

  /// Whether [root] looks like a Dart SDK: a `version` file next to the core
  /// library metadata the analyzer reads.
  static bool _isSdkRoot(String root) =>
      File(p.join(root, 'version')).existsSync() &&
      Directory(p.join(root, 'lib', '_internal', 'sdk_library_metadata'))
          .existsSync();
}
