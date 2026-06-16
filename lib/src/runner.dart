import 'dart:io';

import 'package:args/args.dart';

import 'cli/options.dart';
import 'modernize_exception.dart';
import 'pipeline/pipeline.dart';
import 'pipeline/transformations.dart';

const _version = '0.1.0';

/// Entry point for the `dart_modernize` CLI.
///
/// Parses [arguments], builds the pipeline, and runs it. All errors are
/// caught here and converted to a non-zero exit code.
Future<void> run(List<String> arguments) async {
  final parser = buildArgParser();

  final ArgResults results;
  try {
    results = parser.parse(arguments);
  } on FormatException catch (e) {
    stderr.writeln('Error: ${e.message}');
    stderr.writeln('Run dart_modernize --help for usage.');
    exit(64);
  }

  if (results['help'] as bool) {
    stdout.writeln('Usage: dart_modernize [options] [path]\n\n${parser.usage}');
    return;
  }

  if (results['version'] as bool) {
    stdout.writeln('dart_modernize $_version');
    return;
  }

  final options = CliOptions.fromResults(results);
  final pipeline = ModernizePipeline(
    options: options,
    transformations: buildTransformations(options),
  );

  try {
    await pipeline.run();
  } on ModernizeException catch (e) {
    stderr.writeln('Error: ${e.message}');
    exit(1);
  } on Exception catch (e) {
    stderr.writeln('Unexpected error: $e');
    exit(1);
  }
}
