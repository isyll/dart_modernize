/// Spec for the transform stage's pass ordering (see doc/ORDERING.md).
///
/// The stage layout is the contract: a pass that builds on another's output sits
/// in a later stage, and a pass that rewrites a whole span runs before the
/// passes that edit inside it. These checks fail if a change breaks that layout.
library;

import 'package:dart_modernize/dart_modernize.dart';
import 'package:dart_modernize/src/pipeline/transformations.dart';
import 'package:test/test.dart';

void main() {
  group('transform stage layering', () {
    test('stages are built in the documented structure', () {
      final stages = buildTransformationStages(
        _options(),
      ).map((s) => s.map((t) => t.name).toList()).toList();

      expect(stages, [
        ['primary-constructors'],
        [
          'switch-expressions',
          'cascades',
          'super-parameters',
          'private-named-parameters',
        ],
        ['inline-return', 'prefer-inferred-types'],
        ['expression-bodies', 'final-locals'],
        ['null-aware-conditionals'],
        ['destructure-for-in', 'destructure-locals'],
        [
          'dot-shorthands',
          'string-interpolation',
          'null-aware-spread',
          'null-aware-elements',
          'abstract-final-classes',
        ],
      ]);
    });

    test('every dependency edge runs producer-before-consumer', () {
      final stageOf = _stageIndex(_options());

      // (producer, consumer): producer must be in a strictly earlier stage.
      const edges = [
        // Container rewrites settle before the inner edits land.
        ('primary-constructors', 'cascades'),
        ('primary-constructors', 'dot-shorthands'),
        // The longest chain: a folded cascade is returned, arrowed, collapsed.
        ('cascades', 'inline-return'),
        ('inline-return', 'expression-bodies'),
        ('expression-bodies', 'dot-shorthands'),
        // switch expressions are produced before their arms are arrowed/collapsed.
        ('switch-expressions', 'expression-bodies'),
        ('switch-expressions', 'dot-shorthands'),
        // prefer-inferred-types drops a redundant annotation, so a declared
        // type is gone before dot-shorthands could turn the value into `.new`.
        ('cascades', 'prefer-inferred-types'),
        ('prefer-inferred-types', 'final-locals'),
        ('prefer-inferred-types', 'dot-shorthands'),
        // a partly-forwarded super(...) is settled before its args collapse.
        ('super-parameters', 'dot-shorthands'),
      ];

      for (final (producer, consumer) in edges) {
        expect(
          stageOf[producer],
          lessThan(stageOf[consumer]!),
          reason: '$producer must run in an earlier stage than $consumer',
        );
      }
    });

    test('finalize passes run fix-all, organize-imports, sort-members, then '
        'sort-constructors-first', () {
      final names = buildFinalizeTransformations(_options()).map((t) => t.name);
      expect(names, [
        'fix-all',
        'organize-imports',
        'sort-members',
        'sort-constructors-first',
      ]);
    });

    test('disabling a pass keeps it in place, just flagged off', () {
      final stages = buildTransformationStages(
        _options(cascades: false, dotShorthands: false),
      );
      final names = stages.expand((s) => s).map((t) => t.name);

      // The full set is still present, in the same layout...
      expect(names, contains('cascades'));
      expect(names, contains('dot-shorthands'));
      // ...with the disabled ones flagged off, not removed.
      expect(
        stages.expand((s) => s).firstWhere((t) => t.name == 'cascades').enabled,
        isFalse,
      );
      expect(
        stages
            .expand((s) => s)
            .firstWhere((t) => t.name == 'dot-shorthands')
            .enabled,
        isFalse,
      );
    });
  });
}

CliOptions _options({
  bool dotShorthands = true,
  bool privateNamedParameters = true,
  bool primaryConstructors = true,
  bool superParameters = true,
  bool switchExpressions = true,
  bool cascades = true,
  bool inlineReturn = true,
  bool finalLocals = true,
  bool expressionBodies = true,
  bool stringInterpolation = true,
  bool nullAwareSpread = true,
  bool nullAwareElements = true,
  bool nullAwareConditionals = true,
  bool destructureForIn = true,
  bool destructureLocals = true,
  bool organizeImports = true,
  bool sortMembers = true,
  bool sortConstructorsFirst = true,
  bool fixAll = true,
  bool abstractFinalClasses = true,
  bool preferInferredTypes = true,
  bool verify = true,
}) => .new(
  path: '.',
  dryRun: false,
  check: false,
  color: null,
  verbose: false,
  verify: verify,
  allowDirty: false,
  lineEndings: .auto,
  excludes: const [],
  dotShorthands: dotShorthands,
  privateNamedParameters: privateNamedParameters,
  primaryConstructors: primaryConstructors,
  superParameters: superParameters,
  switchExpressions: switchExpressions,
  cascades: cascades,
  inlineReturn: inlineReturn,
  finalLocals: finalLocals,
  expressionBodies: expressionBodies,
  stringInterpolation: stringInterpolation,
  nullAwareSpread: nullAwareSpread,
  nullAwareElements: nullAwareElements,
  nullAwareConditionals: nullAwareConditionals,
  destructureForIn: destructureForIn,
  destructureLocals: destructureLocals,
  organizeImports: organizeImports,
  sortMembers: sortMembers,
  sortConstructorsFirst: sortConstructorsFirst,
  fixAll: fixAll,
  abstractFinalClasses: abstractFinalClasses,
  preferInferredTypes: preferInferredTypes,
);

/// Maps each structural pass name to the index of the stage it runs in.
Map<String, int> _stageIndex(CliOptions options) {
  final index = <String, int>{};
  final stages = buildTransformationStages(options);
  for (var i = 0; i < stages.length; i++) {
    for (final t in stages[i]) {
      index[t.name] = i;
    }
  }
  return index;
}
