import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// The lint rules [projectPath]/`analysis_options.yaml` turns on.
///
/// The analyzer the tool embeds has no lint rules registered, so it cannot
/// answer "is this lint enabled?" itself; the options file is read directly.
/// Both forms of `linter: rules:` count (a list of names, or a map of names to
/// `true`), and an `include:` of a relative file is followed. A `package:`
/// include (`flutter_lints`, `lints`) is not: none of the rules the passes ask
/// about is in those sets.
Set<String> enabledLintRules(String projectPath) {
  final rules = <String, bool>{};
  _read(File(p.join(projectPath, 'analysis_options.yaml')), rules, {});
  return {
    for (final MapEntry(:key, :value) in rules.entries)
      if (value) key,
  };
}

void _read(File file, Map<String, bool> rules, Set<String> seen) {
  if (!file.existsSync() || !seen.add(p.canonicalize(file.path))) return;
  final Object? yaml;
  try {
    yaml = loadYaml(file.readAsStringSync());
  } on YamlException {
    return;
  }
  if (yaml is! YamlMap) return;

  // Included files come first, so the including file's own rules win.
  final include = yaml['include'];
  for (final entry in [if (include is YamlList) ...include else include]) {
    if (entry is! String || entry.contains(':')) continue;
    _read(File(p.join(p.dirname(file.path), entry)), rules, seen);
  }

  final linter = yaml['linter'];
  final listed = linter is YamlMap ? linter['rules'] : null;
  if (listed is YamlList) {
    for (final name in listed.whereType<String>()) {
      rules[name] = true;
    }
  } else if (listed is YamlMap) {
    for (final MapEntry(:key, :value) in listed.entries) {
      if (value is bool) rules['$key'] = value;
    }
  }
}
