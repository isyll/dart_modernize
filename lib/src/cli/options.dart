import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import '../engine/text_shape.dart';
import 'config.dart';

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
  'null-aware-conditionals',
  'destructure-for-in',
  'destructure-locals',
  'collection-elements',
  'inline-return',
  'final-locals',
  'abstract-final-classes',
  'prefer-inferred-types',
  'sort-constructors-first',
  'constructor-shorthands',
  'empty-bodies',
  'future-pause',
  'wildcard-parameters',
  'null-aware-calls',
  'unmodifiable-of',
];

/// Transformations that are off by default.
///
/// Every other pass in [transformationNames] runs unless turned off; a pass
/// named here runs only when selected with `--only` or switched on with its
/// `--<name>` flag. sort-members only reorders declarations and never changes
/// behavior, but it is the biggest source of diff noise, and
/// collection-elements turns a run of statements into one expression, a larger
/// structural change than any other pass makes, so both are opt-in.
/// unmodifiable-of changes how a constructor call infers its type arguments,
/// so it only runs when asked for.
const defaultOffTransformations = <String>{
  'sort-members',
  'collection-elements',
  'unmodifiable-of',
};

/// The settings each pass accepts under `options:` in the `dart_modernize:`
/// section of `analysis_options.yaml`, with their defaults.
///
/// They tune a pass without switching it off: `dot-shorthands` with
/// `constructors: false` keeps `InputDecoration(...)` written out while still
/// shortening `.center` and `.zero`, and `primary-constructors` with
/// `super-parameters: true` also promotes classes that forward `super.key`.
const passSettings = <String, Map<String, bool>>{
  'dot-shorthands': {'constructors': true},
  'primary-constructors': {'super-parameters': false},
};

/// The name `--no-format` and the config's `disabled:` list use for the final
/// `dart format` step. It is not a pass: `--only` never selects or drops it.
const formatStepName = 'format';

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
        'CI. It counts every step a real run takes, dart fix and dart format '
        'included. On its own it prints just a summary line; combine it with '
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
        'Check that the result still compiles: after each stage in memory, then '
        'with dart analyze over the whole project once files are written. A '
        'change behind a new error is undone, and the run exits with code 2 '
        'when it had to undo any. On by default; --no-verify skips the checks.',
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
  ..addFlag(
    'format',
    defaultsTo: true,
    help:
        'Run dart format over the files the tool changed. Files it did not '
        'touch are never reformatted. --no-format leaves formatting alone.',
  )
  ..addOption(
    'line-length',
    valueHelp: 'columns',
    help:
        'Page width for dart format. Default: the formatter: page_width of '
        'analysis_options.yaml, else 80.',
  )
  ..addFlag(
    'upgrade-sdk',
    negatable: false,
    defaultsTo: false,
    help:
        'Raise the pubspec.yaml SDK constraint to ^3.13.0 first, run pub get, '
        'and remove the final and var modifiers Dart 3.13 no longer allows on '
        'ordinary parameters, then modernize. Requires a clean Git tree.',
  )
  ..addFlag(
    'restore',
    negatable: false,
    defaultsTo: false,
    help:
        'Put back the files saved by a run that was interrupted (a crash or a '
        'kill) before it could finish, then exit.',
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
    'Transformations. All run by default except sort-members, '
    'collection-elements and unmodifiable-of, which are off (switch them on '
    'with --sort-members, --collection-elements and --unmodifiable-of). '
    'Narrow the run to a subset with '
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
    'no-null-aware-conditionals',
    negatable: false,
    help:
        'Skip null-aware-conditionals: collapse `x == null ? null : x[i]` to '
        '`x?[i]` and `x != null ? x.foo : d` to `x?.foo ?? d`. Covers only the '
        'forms `dart fix` leaves behind.',
  )
  ..addFlag(
    'no-destructure-for-in',
    negatable: false,
    help:
        'Skip destructure-for-in: move a for-in variable\'s field reads into an '
        'object pattern, so `for (final e in map.entries)` reading `e.key` and '
        '`e.value` becomes `for (final MapEntry(:key, :value) in map.entries)`.',
  )
  ..addFlag(
    'no-destructure-locals',
    negatable: false,
    help:
        'Skip destructure-locals: collapse a local that only exists to read '
        'fields off it into one destructuring declaration, so `final p = get(); '
        'final x = p.x;` becomes `final Point(:x) = get();`.',
  )
  ..addFlag(
    'collection-elements',
    negatable: false,
    help:
        'Switch on collection-elements (off by default): fold a run of '
        'add/addAll calls on a freshly declared empty literal into one literal '
        'using collection-if and collection-for elements. It restructures '
        'statements into an expression, so it is opt-in.',
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
  )
  ..addFlag(
    'no-constructor-shorthands',
    negatable: false,
    help:
        'Skip constructor-shorthands: declare constructors without repeating '
        'the class name, so `Point(...)` becomes `new(...)` and `factory '
        'Point.fromJson` becomes `factory fromJson` (Dart 3.13).',
  )
  ..addFlag(
    'no-empty-bodies',
    negatable: false,
    help:
        'Skip empty-bodies: end a class, mixin, extension type, or extension '
        'with an empty body in `;` instead of `{}` (Dart 3.13).',
  )
  ..addFlag(
    'no-future-pause',
    negatable: false,
    help:
        'Skip future-pause: write an awaited `Future.delayed(d)` with no '
        'callback as `Future.pause(d)` (Dart 3.13).',
  )
  ..addFlag(
    'no-wildcard-parameters',
    negatable: false,
    help:
        'Skip wildcard-parameters: rename unused `__` and `___` parameters to '
        '`_`, which can repeat since Dart 3.7.',
  )
  ..addFlag(
    'no-null-aware-calls',
    negatable: false,
    help:
        'Skip null-aware-calls: collapse `if (x != null) x.f()` into '
        '`x?.f()`, and `if (cb != null) cb!()` into `cb?.call()`.',
  )
  ..addFlag(
    'unmodifiable-of',
    negatable: false,
    help:
        'Switch on unmodifiable-of (off by default): write '
        '`List.unmodifiable(x)` as `List.unmodifiableOf(x)` (and the same for '
        'Set and Map) when the result keeps its static type.',
  );

/// The single target path from the positional arguments, absolute and
/// normalized.
///
/// Positional arguments are always target paths (transformation selection is
/// explicit via `--only`), so a directory named like a pass is never mistaken
/// for one. At most one path is allowed. Normalizing yields an absolute path
/// with the platform separator (e.g. `dart_modernize C:/proj` on Windows), so
/// the analyzer never sees mixed separators. The runner also uses this to find
/// the project's `analysis_options.yaml` before building [CliOptions].
String resolveTargetPath(ArgResults results) {
  final paths = results.rest;
  if (paths.length > 1) {
    throw FormatException(
      'Expected at most one target path, but got: ${paths.join(', ')}.',
    );
  }
  return p.normalize(p.absolute(paths.isEmpty ? p.current : paths.first));
}

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
    required this.nullAwareConditionals,
    required this.destructureForIn,
    required this.destructureLocals,
    required this.collectionElements,
    required this.finalLocals,
    required this.abstractFinalClasses,
    required this.preferInferredTypes,
    required this.sortConstructorsFirst,
    this.constructorShorthands = true,
    this.emptyBodies = true,
    this.futurePause = true,
    this.wildcardParameters = true,
    this.nullAwareCalls = true,
    this.unmodifiableOf = false,
    this.format = true,
    this.lineLength,
    this.upgradeSdk = false,
    this.restore = false,
    this.dotShorthandConstructors = true,
    this.promoteSuperParameters = false,
    this.lintFixes = const [],
  });

  factory CliOptions.fromResults(
    ArgResults results, {
    DartModernizeConfig config = const .empty(),
  }) {
    // `--only` is an allow-list, and the config's enabled/disabled lists select
    // passes too. Validate every name against the same allow-list up front so a
    // typo fails fast with the full list instead of silently doing nothing.
    final only = results['only'] as List<String>;
    final configNames = {
      ...config.enabled,
      ...config.disabled,
    }.where((name) => name != formatStepName);
    for (final name in [...only, ...configNames]) {
      if (!transformationNames.contains(name)) {
        throw FormatException(
          '"$name" is not a known transformation. '
          'Valid transformations: ${transformationNames.join(', ')}.',
        );
      }
    }
    final bothInConfig = config.enabled.intersection(config.disabled);
    if (bothInConfig.isNotEmpty) {
      throw FormatException(
        'analysis_options.yaml dart_modernize: '
        '${bothInConfig.join(', ')} listed under both enabled and disabled.',
      );
    }
    final selected = only.toSet();
    final settings = _passSettings(config);

    final lineLengthText = results['line-length'] as String?;
    final int? lineLength;
    if (lineLengthText == null) {
      lineLength = config.lineLength;
    } else {
      lineLength = int.tryParse(lineLengthText);
      if (lineLength == null || lineLength <= 0) {
        throw FormatException(
          '--line-length expects a positive number of columns, got '
          '"$lineLengthText".',
        );
      }
    }

    // Each pass is resolved in layers, later layers winning:
    //   1. its built-in default (on, or off for defaultOffTransformations);
    //   2. the config's enabled/disabled lists;
    //   3. `--only`, which when given is the absolute base set (CLI beats
    //      config), so a config list no longer contributes to the base; and
    //   4. the pass's one CLI switch, highest of all: an on-by-default pass has
    //      --no-<name> (forces off), an off-by-default pass has --<name>
    //      (forces on). A switch composes with --only, and where a pass has no
    //      switch for the wanted direction, `--only` is the way to override the
    //      config.
    bool enabled(String name) {
      final defaultOn = !defaultOffTransformations.contains(name);
      final bool base;
      if (selected.isNotEmpty) {
        base = selected.contains(name);
      } else if (config.enabled.contains(name)) {
        base = true;
      } else if (config.disabled.contains(name)) {
        base = false;
      } else {
        base = defaultOn;
      }
      return defaultOn
          ? base && !(results['no-$name'] as bool)
          : base || (results[name] as bool);
    }

    return .new(
      path: resolveTargetPath(results),
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
      excludes: [...config.excludes, ...results['exclude'] as List<String>],
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
      nullAwareConditionals: enabled('null-aware-conditionals'),
      destructureForIn: enabled('destructure-for-in'),
      destructureLocals: enabled('destructure-locals'),
      collectionElements: enabled('collection-elements'),
      finalLocals: enabled('final-locals'),
      abstractFinalClasses: enabled('abstract-final-classes'),
      preferInferredTypes: enabled('prefer-inferred-types'),
      sortConstructorsFirst: enabled('sort-constructors-first'),
      constructorShorthands: enabled('constructor-shorthands'),
      emptyBodies: enabled('empty-bodies'),
      futurePause: enabled('future-pause'),
      wildcardParameters: enabled('wildcard-parameters'),
      nullAwareCalls: enabled('null-aware-calls'),
      unmodifiableOf: enabled('unmodifiable-of'),
      format:
          (results['format'] as bool) &&
          !config.disabled.contains(formatStepName),
      lineLength: lineLength,
      upgradeSdk: results['upgrade-sdk'] as bool,
      restore: results['restore'] as bool,
      dotShorthandConstructors: settings['dot-shorthands']!['constructors']!,
      promoteSuperParameters:
          settings['primary-constructors']!['super-parameters']!,
      lintFixes: config.lintFixes,
    );
  }

  /// [passSettings] with the config's `options:` applied over the defaults.
  ///
  /// An unknown pass, an unknown setting, or a value of the wrong type fails
  /// with the accepted names, like an unknown pass name does.
  static Map<String, Map<String, bool>> _passSettings(
    DartModernizeConfig config,
  ) {
    final resolved = {
      for (final MapEntry(:key, :value) in passSettings.entries)
        key: Map.of(value),
    };
    for (final MapEntry(key: pass, value: values)
        in config.passOptions.entries) {
      final known = resolved[pass];
      if (known == null) {
        throw FormatException(
          'analysis_options.yaml dart_modernize: "$pass" has no options. '
          'Passes with options: ${passSettings.keys.join(', ')}.',
        );
      }
      for (final MapEntry(:key, :value) in values.entries) {
        if (!known.containsKey(key)) {
          throw FormatException(
            'analysis_options.yaml dart_modernize: "$key" is not an option of '
            '$pass. Its options: ${known.keys.join(', ')}.',
          );
        }
        if (value is! bool) {
          throw FormatException(
            'analysis_options.yaml dart_modernize: $pass $key must be true or '
            'false.',
          );
        }
        known[key] = value;
      }
    }
    return resolved;
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
  final bool nullAwareConditionals;
  final bool destructureForIn;
  final bool destructureLocals;
  final bool collectionElements;
  final bool finalLocals;
  final bool abstractFinalClasses;

  final bool preferInferredTypes;
  final bool sortConstructorsFirst;
  final bool constructorShorthands;
  final bool emptyBodies;
  final bool futurePause;
  final bool wildcardParameters;
  final bool nullAwareCalls;
  final bool unmodifiableOf;

  /// When true, `dart format` runs over the files the tool changed.
  final bool format;

  /// Page width for `dart format`, or null to use the project's own.
  final int? lineLength;

  /// When true, raise the project's SDK constraint to the tool's floor before
  /// modernizing.
  final bool upgradeSdk;

  /// When true, put back the files an interrupted run saved, then stop.
  final bool restore;

  /// dot-shorthands `constructors:` setting: whether `Foo(...)` may become
  /// `.new(...)`. Static members and enum values collapse either way.
  final bool dotShorthandConstructors;

  /// primary-constructors `super-parameters:` setting: whether a class whose
  /// constructor forwards `super.` parameters is promoted too.
  final bool promoteSuperParameters;

  /// Lints whose `dart fix` corrections run even when the project does not
  /// enable them.
  final List<String> lintFixes;
}
