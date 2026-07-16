import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import '../engine/text_shape.dart';

/// The name of every transformation, in the order the parser lists them.
///
/// This is the allow-list for positional transformation selection: naming one
/// of these as a positional argument runs only that pass. It must stay in sync
/// with the `--<transformation>` flags declared in [buildArgParser] and with the
/// `name` of each pass in `lib/src/pipeline/transformations/`; the
/// positional-selection test cross-checks it against the test harness's feature
/// map.
const transformationNames = <String>[
  'dot-shorthands',
  'private-named-parameters',
  'primary-constructors',
  'super-parameters',
  'switch-expressions',
  'expression-bodies',
  'organize-imports',
  'sort-members',
  'fix-all',
  'cascades',
  'string-interpolation',
  'null-aware-spread',
  'null-aware-elements',
  'inline-return',
  'final-locals',
  'abstract-final-classes',
  'prefer-inferred-types',
  'sort-constructors-first',
];

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
  ..addFlag(
    'color',
    help:
        'Use ANSI colors in output. Default: auto-detect terminal. '
        '--no-color also disables color when NO_COLOR env var is absent.',
    defaultsTo: null,
  )
  ..addFlag(
    'verbose',
    help: 'Print per-file progress and passes with no changes.',
    negatable: false,
    defaultsTo: false,
  )
  ..addMultiOption(
    'exclude',
    help: 'Additional glob patterns to exclude (can be repeated).',
    valueHelp: 'glob',
  )
  ..addFlag(
    'verify',
    defaultsTo: true,
    help:
        'After editing, re-analyze the changed files and revert any that gain '
        'a new error, then exit non-zero. --no-verify skips the extra analysis.',
  )
  ..addOption(
    'line-endings',
    allowed: ['auto', 'lf', 'crlf'],
    defaultsTo: 'auto',
    valueHelp: 'auto|lf|crlf',
    help:
        "Line endings for files the tool rewrites. auto keeps each file's "
        'existing endings (the default); lf or crlf forces one. A UTF-8 BOM is '
        'always preserved.',
  )
  ..addSeparator(
    'Transformations (all run by default). Name one or more as positional '
    'arguments to run only those, e.g. `dart_modernize cascades '
    'inline-return`; otherwise turn individual passes off with the '
    '--no-<name> flags below.',
  )
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
  )
  ..addFlag(
    'inline-return',
    defaultsTo: true,
    help:
        'Inline a local variable that is declared, immediately returned, and '
        'used nowhere else.',
  )
  ..addFlag(
    'final-locals',
    defaultsTo: true,
    help:
        'Replace `var` with `final` on local variable declarations that are '
        'never reassigned, incremented, or compound-assigned.',
  )
  ..addFlag(
    'abstract-final-classes',
    defaultsTo: true,
    help:
        'Add `abstract final` to classes that expose only static members and '
        'are never instantiated, extended, implemented, or mixed in.',
  )
  ..addFlag(
    'prefer-inferred-types',
    defaultsTo: true,
    help:
        'Remove a redundant explicit type annotation when the initializer\'s '
        'inferred static type is exactly the declared type and that type is '
        'obvious from the initializer (a non-obvious initializer such as a '
        'method call or property access keeps its annotation). Applies to local '
        'variables (final/const/bare-typed), top-level consts, and '
        'final/const fields with an initializer.',
  )
  ..addFlag(
    'sort-constructors-first',
    defaultsTo: true,
    help:
        'Move constructor declarations before all other class members, '
        'satisfying the sort_constructors_first lint rule.',
  );

/// Whether [arg] is unmistakably a filesystem path rather than a bare word.
///
/// Lets a positional argument be classified without touching the disk when it
/// contains a separator, is `.`/`..`, is absolute, or names a Dart file. A bare
/// word (`cascades`, `lib`) is only resolved to a path once it is ruled out as a
/// transformation name and confirmed to exist on disk.
bool _looksLikePath(String arg) =>
    arg.contains('/') ||
    arg.contains(r'\') ||
    arg == '.' ||
    arg == '..' ||
    p.isAbsolute(arg) ||
    arg.endsWith('.dart');

/// Parsed and validated CLI options, passed through the pipeline.
final class CliOptions {
  const CliOptions({
    required this.path,
    required this.dryRun,
    required this.color,
    required this.verbose,
    required this.verify,
    required this.lineEndings,
    required this.excludes,
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
    required this.inlineReturn,
    required this.stringInterpolation,
    required this.nullAwareSpread,
    required this.nullAwareElements,
    required this.finalLocals,
    required this.abstractFinalClasses,
    required this.preferInferredTypes,
    required this.sortConstructorsFirst,
  });

  factory CliOptions.fromResults(ArgResults results) {
    // Positional arguments do double duty. A token that names a transformation
    // selects just that pass (an allow-list); any other token is the target
    // path. Naming any pass overrides the individual --<name> flags and turns
    // every unnamed pass off; naming none leaves each pass at its flag's value
    // (all on by default). Flag names double as pass names, so `results[name]`
    // reads the matching flag.
    final selected = <String>{};
    final paths = <String>[];
    for (final arg in results.rest) {
      if (transformationNames.contains(arg)) {
        selected.add(arg);
      } else if (_looksLikePath(arg) || Directory(arg).existsSync()) {
        paths.add(arg);
      } else {
        throw FormatException(
          '"$arg" is not a known transformation or an existing directory. '
          'Valid transformations: ${transformationNames.join(', ')}.',
        );
      }
    }
    if (paths.length > 1) {
      throw FormatException(
        'Expected at most one target path, but got: ${paths.join(', ')}.',
      );
    }

    bool enabled(String name) =>
        selected.isEmpty ? results[name] as bool : selected.contains(name);
    return .new(
      // Normalize so the analyzer always receives an absolute path with the
      // platform's separator (e.g. `dart_modernize C:/proj` on Windows).
      path: p.normalize(p.absolute(paths.isEmpty ? p.current : paths.first)),
      dryRun: results['dry-run'] as bool,
      color: results['color'] as bool?,
      verbose: results['verbose'] as bool,
      verify: results['verify'] as bool,
      lineEndings: switch (results['line-endings'] as String) {
        'lf' => LineEndings.lf,
        'crlf' => LineEndings.crlf,
        _ => LineEndings.auto,
      },
      excludes: results['exclude'] as List<String>,
      dotShorthands: enabled('dot-shorthands'),
      privateNamedParameters: enabled('private-named-parameters'),
      primaryConstructors: enabled('primary-constructors'),
      superParameters: enabled('super-parameters'),
      switchExpressions: enabled('switch-expressions'),
      expressionBodies: enabled('expression-bodies'),
      organizeImports: enabled('organize-imports'),
      sortMembers: enabled('sort-members'),
      fixAll: enabled('fix-all'),
      cascades: enabled('cascades'),
      inlineReturn: enabled('inline-return'),
      stringInterpolation: enabled('string-interpolation'),
      nullAwareSpread: enabled('null-aware-spread'),
      nullAwareElements: enabled('null-aware-elements'),
      finalLocals: enabled('final-locals'),
      abstractFinalClasses: enabled('abstract-final-classes'),
      preferInferredTypes: enabled('prefer-inferred-types'),
      sortConstructorsFirst: enabled('sort-constructors-first'),
    );
  }

  /// Absolute path to the project root to modernize.
  final String path;

  /// When true, only prints a diff; no files are written.
  final bool dryRun;

  /// null = auto-detect terminal; true = force on; false = force off.
  final bool? color;

  /// When true, emit per-file progress and passes that made no changes.
  final bool verbose;

  /// When true, re-analyze changed files after editing and revert any that
  /// gain a new error. Off with `--no-verify`.
  final bool verify;

  /// How to write line endings back to edited files. Defaults to
  /// [LineEndings.auto], which keeps each file's original ending and BOM.
  final LineEndings lineEndings;

  /// Additional glob patterns supplied via `--exclude` flags.
  final List<String> excludes;

  /// Whether each transformation pass is enabled.
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
  final bool inlineReturn;
  final bool stringInterpolation;
  final bool nullAwareSpread;
  final bool nullAwareElements;
  final bool finalLocals;
  final bool abstractFinalClasses;

  final bool preferInferredTypes;

  final bool sortConstructorsFirst;
}
