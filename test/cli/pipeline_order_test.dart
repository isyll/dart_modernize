/// Spec for the pipeline's fixed pass order.
///
/// Order is part of the contract: structural rewrites (dot shorthands, private
/// named parameters, primary constructors) run before cosmetic ones (organize
/// imports, sort members) and bulk fixes (fix-all) last, so each later pass sees
/// the output of the earlier ones. `buildTransformations` is the single source
/// of that order; the pipeline only filters it by `enabled` at run time.
library;

import 'package:dart_modernize/dart_modernize.dart';
import 'package:dart_modernize/src/pipeline/transformations.dart';
import 'package:test/test.dart';

void main() {
  group('pipeline order', () {
    test('passes are built in the fixed documented order', () {
      final names = buildTransformations(_options()).map((t) => t.name);
      expect(names, _documentedOrder);
    });

    test('every structural pass precedes every cosmetic and bulk pass', () {
      // The documented rationale (see doc/ORDERING.md): shape-changing passes
      // run ahead of the whole-file reorderers and the bulk catch-all. Encoded
      // as an invariant so a reordering that violates it fails here, not just
      // the exact-list check above.
      final order = buildTransformations(
        _options(),
      ).map((t) => t.name).toList();
      final lastStructural = _structural
          .map(order.indexOf)
          .reduce((a, b) => a > b ? a : b);
      final firstCosmetic = _cosmeticAndBulk
          .map(order.indexOf)
          .reduce((a, b) => a < b ? a : b);
      expect(
        lastStructural,
        lessThan(firstCosmetic),
        reason: 'structural passes must all come before cosmetic/bulk passes',
      );
    });

    test('disabling passes preserves the order of the rest', () {
      final transforms = buildTransformations(
        _options(privateNamedParameters: false, organizeImports: false),
      );

      // The full canonical sequence is always present...
      expect(transforms.map((t) => t.name), _documentedOrder);

      // ...with the disabled ones flagged, not removed or reordered.
      expect(
        transforms
            .firstWhere((t) => t.name == 'private-named-parameters')
            .enabled,
        isFalse,
      );
      expect(
        transforms.firstWhere((t) => t.name == 'organize-imports').enabled,
        isFalse,
      );

      // What actually runs is the enabled subset, still in canonical order.
      expect(transforms.where((t) => t.enabled).map((t) => t.name), [
        'dot-shorthands',
        'primary-constructors',
        'super-parameters',
        'switch-expressions',
        'cascades',
        'inline-return',
        'final-locals',
        'expression-bodies',
        'string-interpolation',
        'null-aware-spread',
        'null-aware-elements',
        'sort-members',
        'fix-all',
        'abstract-final-classes',
      ]);
    });
  });
}

/// Whole-file reorderers and the bulk catch-all: they run after structure is
/// settled.
const _cosmeticAndBulk = <String>[
  'organize-imports',
  'sort-members',
  'fix-all',
  'abstract-final-classes',
];

const _documentedOrder = <String>[
  'dot-shorthands',
  'private-named-parameters',
  'primary-constructors',
  'super-parameters',
  'switch-expressions',
  'cascades',
  'inline-return',
  'final-locals',
  'expression-bodies',
  'string-interpolation',
  'null-aware-spread',
  'null-aware-elements',
  'organize-imports',
  'sort-members',
  'fix-all',
  'abstract-final-classes',
];

/// Shape-changing passes: they rewrite declarations and statements.
const _structural = <String>[
  'dot-shorthands',
  'private-named-parameters',
  'primary-constructors',
  'super-parameters',
  'switch-expressions',
  'cascades',
  'inline-return',
  'final-locals',
  'expression-bodies',
  'string-interpolation',
  'null-aware-spread',
  'null-aware-elements',
];

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
  bool organizeImports = true,
  bool sortMembers = true,
  bool fixAll = true,
  bool abstractFinalClasses = true,
}) => .new(
  path: '.',
  dryRun: false,
  color: null,
  verbose: false,
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
  organizeImports: organizeImports,
  sortMembers: sortMembers,
  fixAll: fixAll,
  abstractFinalClasses: abstractFinalClasses,
);
