import 'dart:io';

import 'package:args/args.dart';

const _version = '0.1.0';

void run(List<String> arguments) {
  final parser = ArgParser()
    ..addFlag('help', abbr: 'h', help: 'Show usage.', negatable: false)
    ..addFlag('version', abbr: 'v', help: 'Show version.', negatable: false);

  final ArgResults results;
  try {
    results = parser.parse(arguments);
  } on FormatException catch (e) {
    stderr.writeln('Error: ${e.message}');
    stderr.writeln('Run dart_modernize --help for usage.');
    exit(64);
  }

  if (results['help'] as bool) {
    print('Usage: dart_modernize [options] <path>\n${parser.usage}');
    return;
  }

  if (results['version'] as bool) {
    print('dart_modernize $_version');
    return;
  }

  stderr.writeln('No command given. Run dart_modernize --help for usage.');
  exit(64);
}
