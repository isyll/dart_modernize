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

const List<String> _documentedOrder = [
  'dot-shorthands',
  'private-named-parameters',
  'primary-constructors',
  'switch-expressions',
  'organize-imports',
  'sort-members',
  'fix-all',
];

CliOptions _options({
  bool dotShorthands = true,
  bool privateNamedParameters = true,
  bool primaryConstructors = true,
  bool switchExpressions = true,
  bool organizeImports = true,
  bool sortMembers = true,
  bool fixAll = true,
}) => CliOptions(
  path: '.',
  dryRun: false,
  dotShorthands: dotShorthands,
  privateNamedParameters: privateNamedParameters,
  primaryConstructors: primaryConstructors,
  switchExpressions: switchExpressions,
  organizeImports: organizeImports,
  sortMembers: sortMembers,
  fixAll: fixAll,
);

void main() {
  group('pipeline order', () {
    test('passes are built in the fixed documented order', () {
      final names = buildTransformations(_options()).map((t) => t.name);
      expect(names, _documentedOrder);
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
        'switch-expressions',
        'sort-members',
        'fix-all',
      ]);
    });
  });
}
