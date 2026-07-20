import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import '../engine/text_shape.dart';

/// The name of every transformation, in the order the parser lists them.
///
/// This is the allow-list for `--only`: naming one of these runs just that
/// pass. It must stay in sync with the `--no-<name>` flags declared in
/// [buildArgParser] and with the `name` of each pass in
/// `lib/src/pipeline/transformations/`; the selection test cross-checks it
/// against the test harness's feature map.
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

/// Transformations that are off by default.
///
/// Every other pass in [transformationNames] runs unless turned off; a pass
/// named here runs only when selected with `--only` or switched on with its
/// `--<name>` flag. sort-members only reorders declarations and never changes
/// behavior, but it is the single biggest source of diff noise, so it is
/// opt-in.
const defaultOffTransformations = <String>{'sort-members'};

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
    'check',
    negatable: false,
    defaultsTo: false,
    help:
        'Exit non-zero if any file would change and write nothing, for gating '
        'CI. On its own it prints just a summary line; combine it with '
        '--dry-run to also print the diff.',
  )
  ..addFlag(
    'color',
    help:
        'Force ANSI color in output on or off. Default: auto-detect, so color '
        'is on when writing to a terminal and off when piped or when NO_COLOR '
        'is set. Pass --color to force it on (e.g. when piping to a pager) or '
        '--no-color to force it off.',
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
        'a new error, then exit non-zero. On by default; --no-verify skips the '
        'extra analysis.',
  )
  ..addFlag(
    'allow-dirty',
    negatable: false,
    defaultsTo: false,
    help:
        'Run even when the Git working tree has uncommitted changes. By '
        'default the tool refuses, so its edits land in their own reviewable '
        'diff.',
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
  ..addMultiOption(
    'only',
    valueHelp: 'name',
    help:
        'Run only the named passes and skip every other one. Repeat the option '
        'or comma-separate names to select several, e.g. `--only '
        'cascades,inline-return`. Names are the passes listed below. Without '
        '--only, every pass runs.',
  )
  ..addSeparator(
    'Transformations. All run by default except sort-members, which is off '
    '(switch it on with --sort-members). Narrow the run to a subset with '
    '--only, or turn an on-by-default pass off with its --no-<name> switch '
    'below. Order never matters: passes always run in their fixed pipeline '
    'order.',
  )
  ..addFlag(
    'no-dot-shorthands',
    negatable: false,
    help:
        'Skip dot-shorthands: collapse ClassName.member to .member where the '
        'context type is unambiguous.',
  )
  ..addFlag(
    'no-private-named-parameters',
    negatable: false,
    help:
        'Skip private-named-parameters: fold constructor boilerplate into '
        'private named parameter form.',
  )
  ..addFlag(
    'no-primary-constructors',
    negatable: false,
    help:
        'Skip primary-constructors: promote eligible classes to primary '
        'constructor form when safe.',
  )
  ..addFlag(
    'no-super-parameters',
    negatable: false,
    help:
        'Skip super-parameters: forward constructor parameters to the '
        'superclass with super.x when passed through unchanged.',
  )
  ..addFlag(
    'no-switch-expressions',
    negatable: false,
    help:
        'Skip switch-expressions: rewrite eligible statement switches as '
        'switch expressions using modern pattern syntax.',
  )
  ..addFlag(
    'no-expression-bodies',
    negatable: false,
    help:
        'Skip expression-bodies: collapse single-statement block bodies into '
        'concise => bodies for functions, methods, getters, and closures.',
  )
  ..addFlag(
    'no-organize-imports',
    negatable: false,
    help: 'Skip organize-imports: sort, group, and prune import directives.',
  )
  ..addFlag(
    'sort-members',
    negatable: false,
    help:
        'Switch on sort-members (off by default): reorder class members into '
        'canonical order. It only moves code and never changes behavior, but '
        'it can produce a large diff.',
  )
  ..addFlag(
    'no-fix-all',
    negatable: false,
    help: 'Skip fix-all: apply bulk fixes equivalent to `dart fix`.',
  )
  ..addFlag(
    'no-cascades',
    negatable: false,
    help:
        'Skip cascades: collapse sequential writes to a fresh local into a '
        'cascade chain (.. operator).',
  )
  ..addFlag(
    'no-string-interpolation',
    negatable: false,
    help:
        'Skip string-interpolation: rewrite string concatenation chains as '
        'string interpolation.',
  )
  ..addFlag(
    'no-null-aware-spread',
    negatable: false,
    help:
        'Skip null-aware-spread: replace `if (x != null) ...x` spread guards '
        'with the `...?x` null-aware spread.',
  )
  ..addFlag(
    'no-null-aware-elements',
    negatable: false,
    help:
        'Skip null-aware-elements: replace `if (x != null) x` collection-element '
        'guards with the `?x` null-aware element syntax.',
  )
  ..addFlag(
    'no-inline-return',
    negatable: false,
    help:
        'Skip inline-return: inline a local variable that is declared, '
        'immediately returned, and used nowhere else.',
  )
  ..addFlag(
    'no-final-locals',
    negatable: false,
    help:
        'Skip final-locals: replace `var` with `final` on local variable '
        'declarations that are never reassigned, incremented, or '
        'compound-assigned.',
  )
  ..addFlag(
    'no-abstract-final-classes',
    negatable: false,
    help:
        'Skip abstract-final-classes: add `abstract final` to classes that '
        'expose only static members and are never instantiated, extended, '
        'implemented, or mixed in.',
  )
  ..addFlag(
    'no-prefer-inferred-types',
    negatable: false,
    help:
        'Skip prefer-inferred-types: remove a redundant explicit type '
        'annotation when the initializer makes the type obvious, and expand a '
        'dot-shorthand initializer so the annotation can be dropped. Applies '
        'to local variables, top-level consts, and final/const fields with an '
        'initializer.',
  )
  ..addFlag(
    'no-sort-constructors-first',
    negatable: false,
    help:
        'Skip sort-constructors-first: move constructor declarations before '
        'all other class members, satisfying the sort_constructors_first lint '
        'rule.',
  );

/// Parsed and validated CLI options, passed through the pipeline.
final class CliOptions {
  const CliOptions({
    required this.path,
    required this.dryRun,
    required this.check,
    required this.color,
    required this.verbose,
    required this.verify,
    required this.allowDirty,
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
    // Positional arguments are always target paths. Transformation selection is
    // explicit (`--only` / `--no-<name>`), so a directory named like a pass
    // (e.g. `cascades`) is never mistaken for a selection.
    final paths = results.rest;
    if (paths.length > 1) {
      throw FormatException(
        'Expected at most one target path, but got: ${paths.join(', ')}.',
      );
    }

    // `--only` is an allow-list. Validate each name up front so a typo fails
    // fast with the full list, instead of silently narrowing the run to
    // nothing.
    final only = results['only'] as List<String>;
    for (final name in only) {
      if (!transformationNames.contains(name)) {
        throw FormatException(
          '"$name" is not a known transformation. '
          'Valid transformations: ${transformationNames.join(', ')}.',
        );
      }
    }
    final selected = only.toSet();

    // A pass starts from the selected set (or its default, when nothing is
    // selected), then its one switch overrides: an on-by-default pass has
    // --no-<name> (forces off), an off-by-default pass has --<name> (forces
    // on). So a switch always wins and composes with --only: --no-<name>
    // subtracts from a selection, --<name> adds to it.
    bool enabled(String name) {
      final defaultOn = !defaultOffTransformations.contains(name);
      final inBase = selected.isEmpty ? defaultOn : selected.contains(name);
      return defaultOn
          ? inBase && !(results['no-$name'] as bool)
          : inBase || (results[name] as bool);
    }

    return .new(
      // Normalize so the analyzer always receives an absolute path with the
      // platform's separator (e.g. `dart_modernize C:/proj` on Windows).
      path: p.normalize(p.absolute(paths.isEmpty ? p.current : paths.first)),
      dryRun: results['dry-run'] as bool,
      check: results['check'] as bool,
      color: results['color'] as bool?,
      verbose: results['verbose'] as bool,
      verify: results['verify'] as bool,
      allowDirty: results['allow-dirty'] as bool,
      lineEndings: switch (results['line-endings'] as String) {
        'lf' => .lf,
        'crlf' => .crlf,
        _ => .auto,
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

  /// When true, write nothing and exit non-zero if any file would change, so
  /// the tool can gate CI. Composes with [dryRun] to also print the diff.
  final bool check;

  /// null = auto-detect terminal; true = force on; false = force off.
  final bool? color;

  /// When true, emit per-file progress and passes that made no changes.
  final bool verbose;

  /// When true, re-analyze changed files after editing and revert any that
  /// gain a new error. Off with `--no-verify`.
  final bool verify;

  /// When true, run even if the Git working tree has uncommitted changes.
  /// Off by default, so the tool refuses on a dirty tree.
  final bool allowDirty;

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
