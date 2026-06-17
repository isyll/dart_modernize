import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../modernize_exception.dart';

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

  // TODO: parse the constraint and verify >=3.12.0 is satisfied.
}
