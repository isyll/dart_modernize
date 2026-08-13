import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:yaml/yaml.dart';

import '../modernize_exception.dart';

/// The lowest Dart SDK the modernized output is guaranteed to compile against.
///
/// The transformations emit 3.13+ idioms, so a project whose SDK constraint
/// admits an older version would be broken by them.
///
/// 3.13 is the floor because primary constructors became stable there, and the
/// promotion pass emits that syntax. Refusing up front is better than letting a
/// run reach a project that cannot compile the result.
final Version _minimumSdk = .new(3, 13, 0);

/// Validates that the project at [projectPath] is ready for modernization.
///
/// Throws [ModernizeException] if validation fails.
Future<void> validateProject(String projectPath) async {
  _checkPubspec(projectPath);
}

void _checkPubspec(String projectPath) {
  final pubspecFile = File(p.join(projectPath, 'pubspec.yaml'));
  if (!pubspecFile.existsSync()) {
    throw ModernizeException('No pubspec.yaml found at $projectPath.');
  }

  final raw = loadYaml(pubspecFile.readAsStringSync());
  if (raw is! YamlMap) {
    throw ModernizeException('pubspec.yaml is not a valid YAML map.');
  }

  final environment = raw['environment'];
  if (environment is! YamlMap) {
    throw ModernizeException('pubspec.yaml is missing an environment section.');
  }

  final sdk = environment['sdk']?.toString();
  if (sdk == null) {
    throw ModernizeException(
      'pubspec.yaml is missing an SDK constraint; cannot determine Dart version.',
    );
  }

  final VersionConstraint constraint;
  try {
    constraint = .parse(sdk);
  } on FormatException {
    throw ModernizeException(
      'pubspec.yaml has an invalid SDK constraint: "$sdk".',
    );
  }

  final atLeastMinimum = VersionRange(min: _minimumSdk, includeMin: true);
  if (!atLeastMinimum.allowsAll(constraint)) {
    throw ModernizeException(
      'This tool targets Dart $_minimumSdk or newer, but the project SDK '
      'constraint "$sdk" allows an older version. Raise the pubspec.yaml SDK '
      'constraint to ">=$_minimumSdk <4.0.0" before modernizing.',
    );
  }
}
