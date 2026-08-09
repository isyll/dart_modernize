import 'dart:io';

import 'package:args/args.dart';

import 'cli/config.dart';
import 'cli/options.dart';
import 'modernize_exception.dart';
import 'output/reporter.dart';
import 'pipeline/pipeline.dart';

const _version = '0.9.2';

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
    Reporter(color: resolveColor(colorFlag: null), verbose: false)
      ..error(e.message)
      ..errorHint('Run dart_modernize --help for usage.');
    exit(64);
  }

  final earlyReporter = Reporter(
    color: resolveColor(colorFlag: null),
    verbose: false,
  );

  if (results['help'] as bool) {
    earlyReporter.help(parser.usage);
    return;
  }

  if (results['version'] as bool) {
    earlyReporter.version(_version);
    return;
  }

  final CliOptions options;
  try {
    // Read the project's dart_modernize: config before building options, so the
    // file's enabled/disabled/exclude settings layer in under the CLI flags.
    final config = readDartModernizeConfig(resolveTargetPath(results));
    options = .fromResults(results, config: config);
  } on FormatException catch (e) {
    earlyReporter
      ..error(e.message)
      ..errorHint('Run dart_modernize --help for usage.');
    exit(64);
  }

  final reporter = Reporter(
    color: resolveColor(colorFlag: options.color),
    verbose: options.verbose,
  );
  final pipeline = ModernizePipeline(options: options, reporter: reporter);

  try {
    await pipeline.run();
  } on CheckModifiedException {
    // --check found files that would change. The summary is already printed;
    // exit non-zero so CI fails, with no error output.
    exit(1);
  } on ModernizeException catch (e) {
    reporter.error(e.message);
    exit(1);
  } on Exception catch (e) {
    reporter.unexpectedError(e);
    exit(1);
  }
}
