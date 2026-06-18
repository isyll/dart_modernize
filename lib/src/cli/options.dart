import 'package:args/args.dart';
import 'package:path/path.dart' as p;

/// Builds the [ArgParser] for the `dart_modernize` CLI.
ArgParser buildArgParser() => .new()
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
    'super-parameters',
    defaultsTo: true,
    help:
        'Forward constructor parameters to the superclass with super.x when '
        'passed through unchanged.',
  )
  ..addFlag(
    'switch-expressions',
    defaultsTo: true,
    help:
        'Rewrite eligible statement switches as switch expressions using '
        'modern pattern syntax.',
  )
  ..addFlag(
    'expression-bodies',
    defaultsTo: true,
    help:
        'Collapse single-statement block bodies into concise => bodies for '
        'functions, methods, getters, and closures.',
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
  )
  ..addFlag(
    'cascades',
    defaultsTo: true,
    help:
        'Collapse sequential writes to a fresh local into a cascade chain '
        '(.. operator).',
  )
  ..addFlag(
    'string-interpolation',
    defaultsTo: true,
    help: 'Rewrite string concatenation chains as string interpolation.',
  )
  ..addFlag(
    'null-aware-spread',
    defaultsTo: true,
    help:
        'Replace `if (x != null) ...x` spread guards with the `...?x` '
        'null-aware spread.',
  )
  ..addFlag(
    'null-aware-elements',
    defaultsTo: true,
    help:
        'Replace `if (x != null) x` collection-element guards with the '
        '`?x` null-aware element syntax.',
  );

/// Parsed and validated CLI options, passed through the pipeline.
final class CliOptions {
  /// Absolute path to the project root to modernize.
  final String path;

  /// When true, only prints a diff; no files are written.
  final bool dryRun;

  final bool dotShorthands;

  final bool privateNamedParameters;

  final bool primaryConstructors;
  final bool superParameters;
  final bool switchExpressions;
  final bool expressionBodies;
  final bool organizeImports;
  final bool sortMembers;
  final bool fixAll;
  final bool cascades;
  final bool stringInterpolation;
  final bool nullAwareSpread;
  final bool nullAwareElements;
  const CliOptions({
    required this.path,
    required this.dryRun,
    required this.dotShorthands,
    required this.privateNamedParameters,
    required this.primaryConstructors,
    required this.superParameters,
    required this.switchExpressions,
    required this.expressionBodies,
    required this.organizeImports,
    required this.sortMembers,
    required this.fixAll,
    required this.cascades,
    required this.stringInterpolation,
    required this.nullAwareSpread,
    required this.nullAwareElements,
  });

  factory CliOptions.fromResults(ArgResults results) {
    final rest = results.rest;
    return .new(
      path: p.absolute(rest.isNotEmpty ? rest.first : p.current),
      dryRun: results['dry-run'] as bool,
      dotShorthands: results['dot-shorthands'] as bool,
      privateNamedParameters: results['private-named-parameters'] as bool,
      primaryConstructors: results['primary-constructors'] as bool,
      superParameters: results['super-parameters'] as bool,
      switchExpressions: results['switch-expressions'] as bool,
      expressionBodies: results['expression-bodies'] as bool,
      organizeImports: results['organize-imports'] as bool,
      sortMembers: results['sort-members'] as bool,
      fixAll: results['fix-all'] as bool,
      cascades: results['cascades'] as bool,
      stringInterpolation: results['string-interpolation'] as bool,
      nullAwareSpread: results['null-aware-spread'] as bool,
      nullAwareElements: results['null-aware-elements'] as bool,
    );
  }
}
