import 'dart:io';

import 'package:test/test.dart';

String _read(String path) => File(path).readAsStringSync();

String _match(String source, RegExp pattern, String what) {
  final match = pattern.firstMatch(source);
  if (match == null) fail('Could not find $what.');
  return match.group(1)!;
}

void main() {
  group('release version', () {
    late String pubspec;
    late String runner;
    late String changelog;

    setUpAll(() {
      pubspec = _match(
        _read('pubspec.yaml'),
        RegExp(r'^version:\s*(\S+)\s*$', multiLine: true),
        'the pubspec.yaml version',
      );
      runner = _match(
        _read('lib/src/runner.dart'),
        RegExp(r"const _version = '([^']+)';"),
        'the _version constant in lib/src/runner.dart',
      );
      changelog = _match(
        _read('CHANGELOG.md'),
        RegExp(r'^## (\d+\.\d+\.\d+)\s*$', multiLine: true),
        'a version heading in CHANGELOG.md',
      );
    });

    test('runner _version matches pubspec.yaml', () {
      expect(runner, pubspec);
    });

    test('top CHANGELOG.md heading matches pubspec.yaml', () {
      expect(changelog, pubspec);
    });
  });
}
