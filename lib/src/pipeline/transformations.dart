import '../cli/options.dart';
import 'transformation.dart';
import 'transformations/abstract_final_classes.dart';
import 'transformations/cascades.dart';
import 'transformations/dot_shorthands.dart';
import 'transformations/expression_bodies.dart';
import 'transformations/final_locals.dart';
import 'transformations/fix_all.dart';
import 'transformations/inline_return.dart';
import 'transformations/null_aware_elements.dart';
import 'transformations/null_aware_spread.dart';
import 'transformations/organize_imports.dart';
import 'transformations/prefer_inferred_types.dart';
import 'transformations/primary_constructors.dart';
import 'transformations/private_named_parameters.dart';
import 'transformations/sort_members.dart';
import 'transformations/string_interpolation.dart';
import 'transformations/super_parameters.dart';
import 'transformations/switch_expressions.dart';

/// The finalize passes, in execution order. They run after the structural
/// stages have settled, over the files on disk rather than through the per-unit
/// AST loop (see [FinalizeTransformation]).
List<FinalizeTransformation> buildFinalizeTransformations(CliOptions options) =>
    [
      FixAll(enabled: options.fixAll),
      OrganizeImports(enabled: options.organizeImports),
      SortMembers(enabled: options.sortMembers),
    ];

/// Every transformation, flattened across stages and finalize. Used only to
/// answer "is anything enabled at all?".
List<Transformation> buildTransformations(CliOptions options) => [
  for (final stage in buildTransformationStages(options)) ...stage,
  ...buildFinalizeTransformations(options),
];

/// The structural transformation stages, in execution order.
///
/// The transform stage is a fixed, dependency-ordered pipeline: each stage is
/// resolved once and applied as a unit, then the next stage runs against the
/// re-resolved result. There is no "repeat until nothing changes" loop, so the
/// number of resolutions is a compile-time constant and the output is fully
/// deterministic. See doc/ORDERING.md for the dependency graph.
///
/// Two rules fix the layering:
///   * a pass that *consumes* a construct another pass *produces* runs in a
///     later stage (cascades -> inline-return -> expression-bodies -> dot
///     shorthands is the longest such chain);
///   * a pass that copies a span verbatim (primary constructors, cascades, the
///     switch rewrite, ...) runs before the passes that edit inside that span,
///     so a container rewrite never discards an inner edit.
///
/// Passes within one stage are mutually independent: they target disjoint
/// syntactic regions, so their relative order never changes the result.
List<List<Transformation>> buildTransformationStages(CliOptions options) => [
  // 1. Outermost class restructuring. Primary constructors rewrite a whole
  //    class and copy retained members verbatim, so they run first and alone;
  //    later stages modernize those members on the re-resolved tree.
  [PrimaryConstructors(enabled: options.primaryConstructors)],

  // 2. Structural producers: fold statement runs and synthesize the new
  //    constructs (cascades, switch expressions, super/private parameters)
  //    that later stages build on.
  [
    SwitchExpressions(enabled: options.switchExpressions),
    Cascades(enabled: options.cascades),
    SuperParameters(enabled: options.superParameters),
    PrivateNamedParameters(enabled: options.privateNamedParameters),
  ],

  // 3. Consumers of stage 2. inline-return collapses a folded cascade that is
  //    then returned; prefer-inferred-types drops or relocates a redundant type
  //    annotation (including onto a cascade's bare collection target).
  [
    InlineReturn(enabled: options.inlineReturn),
    PreferInferredTypes(enabled: options.preferInferredTypes),
  ],

  // 4. expression-bodies arrows the single-statement body inline-return just
  //    produced; final-locals upgrades the `var` prefer-inferred-types emits.
  [
    ExpressionBodies(enabled: options.expressionBodies),
    FinalLocals(enabled: options.finalLocals),
  ],

  // 5. Innermost edits, run last. By now prefer-inferred-types has dropped
  //    redundant annotations (a dropped type is preferred over a `.new`
  //    shorthand) and every container pass has settled, so dot-shorthands sees
  //    final positions. abstract-final-classes needs the whole project resolved
  //    to its final shape before deciding which classes are safe to seal.
  [
    DotShorthands(enabled: options.dotShorthands),
    StringInterpolation(enabled: options.stringInterpolation),
    NullAwareSpread(enabled: options.nullAwareSpread),
    NullAwareElements(enabled: options.nullAwareElements),
    AbstractFinalClasses(enabled: options.abstractFinalClasses),
  ],
];
