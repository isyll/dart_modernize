import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:yaml/yaml.dart';

import '../modernize_exception.dart';
import 'validator.dart';

/// Raises the `environment: sdk:` constraint of [projectPath]/pubspec.yaml to
/// `^` [minimumSdk] when it admits an older Dart.
///
/// Only the constraint's text is replaced, so comments, quoting elsewhere and
/// the rest of the file stay as written. Returns the previous constraint, or
/// null when it already starts at the floor.
String? raiseSdkConstraint(String projectPath) {
  final file = File(p.join(projectPath, 'pubspec.yaml'));
  if (!file.existsSync()) {
    throw ModernizeException('No pubspec.yaml found at $projectPath.');
  }
  final text = file.readAsStringSync();
  final root = loadYamlNode(text);
  final environment = root is YamlMap ? root.nodes['environment'] : null;
  final sdk = environment is YamlMap ? environment.nodes['sdk'] : null;
  if (sdk is! YamlScalar) {
    throw const ModernizeException(
      'pubspec.yaml has no environment: sdk: constraint to raise.',
    );
  }

  final current = '${sdk.value}';
  final VersionConstraint constraint;
  try {
    constraint = VersionConstraint.parse(current);
  } on FormatException {
    throw ModernizeException(
      'pubspec.yaml has an invalid SDK constraint: "$current".',
    );
  }
  if (VersionRange(min: minimumSdk, includeMin: true).allowsAll(constraint)) {
    return null;
  }

  final span = sdk.span;
  file.writeAsStringSync(
    text.replaceRange(span.start.offset, span.end.offset, '^$minimumSdk'),
  );
  return current;
}
