import 'package:args/args.dart';
import 'package:path/path.dart' as p;

/// Builds the [ArgParser] for the `dart_modernize` CLI.
ArgParser buildArgParser() {
  return ArgParser()
    ..addFlag(
      'help',
      abbr: 'h',
      help: 'Show this usage information.',
      negatable: false,
    )
    ..addFlag(
      'version',
      abbr: 'v',
      help: 'Print the version number.',
      negatable: false,
    )
    ..addFlag(
      'dry-run',
      abbr: 'n',
      help: 'Preview changes without writing any files.',
      negatable: false,
    )
    ..addSeparator('Transformations (all enabled by default):')
    ..addFlag(
      'dot-shorthands',
      defaultsTo: true,
      help:
          'Collapse ClassName.member to .member where the context type is unambiguous.',
    )
    ..addFlag(
      'private-named-parameters',
      defaultsTo: true,
      help: 'Fold constructor boilerplate into private named parameter form.',
    )
    ..addFlag(
      'primary-constructors',
      defaultsTo: true,
      help: 'Promote eligible classes to primary constructor form when safe.',
    )
    ..addFlag(
      'switch-expressions',
      defaultsTo: true,
      help:
          'Rewrite eligible statement switches as switch expressions using '
          'modern pattern syntax.',
    )
    ..addFlag(
      'organize-imports',
      defaultsTo: true,
      help: 'Sort, group, and prune import directives.',
    )
    ..addFlag(
      'sort-members',
      defaultsTo: true,
      help: 'Reorder class members into canonical order.',
    )
    ..addFlag(
      'fix-all',
      defaultsTo: true,
      help: 'Apply bulk fixes equivalent to `dart fix`.',
    );
}

/// Parsed and validated CLI options, passed through the pipeline.
final class CliOptions {
  /// Absolute path to the project root to modernize.
  final String path;

  /// When true, only prints a diff — no files are written.
  final bool dryRun;

  final bool dotShorthands;

  final bool privateNamedParameters;

  final bool primaryConstructors;
  final bool switchExpressions;
  final bool organizeImports;
  final bool sortMembers;
  final bool fixAll;
  const CliOptions({
    required this.path,
    required this.dryRun,
    required this.dotShorthands,
    required this.privateNamedParameters,
    required this.primaryConstructors,
    required this.switchExpressions,
    required this.organizeImports,
    required this.sortMembers,
    required this.fixAll,
  });

  factory CliOptions.fromResults(ArgResults results) {
    final rest = results.rest;
    return .new(
      path: p.absolute(rest.isNotEmpty ? rest.first : p.current),
      dryRun: results['dry-run'] as bool,
      dotShorthands: results['dot-shorthands'] as bool,
      privateNamedParameters: results['private-named-parameters'] as bool,
      primaryConstructors: results['primary-constructors'] as bool,
      switchExpressions: results['switch-expressions'] as bool,
      organizeImports: results['organize-imports'] as bool,
      sortMembers: results['sort-members'] as bool,
      fixAll: results['fix-all'] as bool,
    );
  }
}
