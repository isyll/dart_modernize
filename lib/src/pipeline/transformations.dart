import '../cli/options.dart';
import 'transformation.dart';
import 'transformations/abstract_final_classes.dart';
import 'transformations/cascades.dart';
import 'transformations/collection_elements.dart';
import 'transformations/destructure_for_in.dart';
import 'transformations/destructure_locals.dart';
import 'transformations/dot_shorthands.dart';
import 'transformations/expression_bodies.dart';
import 'transformations/final_locals.dart';
import 'transformations/fix_all.dart';
import 'transformations/inline_return.dart';
import 'transformations/null_aware_conditionals.dart';
import 'transformations/null_aware_elements.dart';
import 'transformations/null_aware_spread.dart';
import 'transformations/organize_imports.dart';
import 'transformations/prefer_inferred_types.dart';
import 'transformations/primary_constructors.dart';
import 'transformations/private_named_parameters.dart';
import 'transformations/sort_constructors_first.dart';
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
      SortConstructorsFirst(enabled: options.sortConstructorsFirst),
    ];

/// Every transformation, flattened across stages and finalize. Used only to
/// answer "is anything enabled at all?".
List<Transformation> buildTransformations(CliOptions options) => [
  for (final stage in buildTransformationStages(options)) ...stage,
  ...buildFinalizeTransformations(options),
];

/// The transform stages, in execution order. Each stage is resolved once and
/// applied before the next stage runs. See doc/ORDERING.md.
///
/// Two rules decide which stage a pass belongs to:
///   * a pass that builds on another pass's output runs in a later stage
///     (cascades -> inline-return -> expression-bodies -> dot-shorthands is the
///     longest such chain);
///   * a pass that rewrites a whole span (primary constructors, cascades, the
///     switch rewrite) runs before the passes that edit inside that span.
///
/// Passes in the same stage touch separate parts of the code, so their order
/// within a stage does not matter.
List<List<Transformation>> buildTransformationStages(CliOptions options) => [
  // 1. Primary constructors rewrite a whole class and copy its other members
  //    verbatim, so they run first; later stages then modernize those members.
  [PrimaryConstructors(enabled: options.primaryConstructors)],

  // 2. collection-elements folds an add/addAll run into one literal. It has to
  //    beat cascades to that run: cascades would otherwise fold the same
  //    statements into `<T>[]..add(a)..add(b)` and leave nothing to collapse.
  [CollectionElements(enabled: options.collectionElements)],

  // 3. Fold statement runs and build the new constructs later stages read.
  [
    SwitchExpressions(enabled: options.switchExpressions),
    Cascades(enabled: options.cascades),
    SuperParameters(enabled: options.superParameters),
    PrivateNamedParameters(enabled: options.privateNamedParameters),
  ],

  // 4. inline-return collapses a folded cascade that is then returned;
  //    prefer-inferred-types drops or relocates a redundant type annotation.
  [
    InlineReturn(enabled: options.inlineReturn),
    PreferInferredTypes(enabled: options.preferInferredTypes),
  ],

  // 5. expression-bodies arrows the body inline-return just produced;
  //    final-locals upgrades the `var` prefer-inferred-types emits.
  [
    ExpressionBodies(enabled: options.expressionBodies),
    FinalLocals(enabled: options.finalLocals),
  ],

  // 6. null-aware-conditionals replaces a whole conditional expression, so it
  //    has to land before the innermost passes edit inside that span (a
  //    fallback arm such as `Color.red` is a dot-shorthand target), and after
  //    the passes that rewrite an enclosing statement (inline-return,
  //    expression-bodies) have already moved the conditional into place.
  [NullAwareConditionals(enabled: options.nullAwareConditionals)],

  // 7. The two destructuring passes rewrite a loop header or a run of
  //    statements plus the reads inside them, so they run after final-locals has
  //    settled the declaration keyword and after null-aware-conditionals has
  //    replaced any conditional wrapping one of those reads, and before the
  //    innermost passes edit the same reads. They target different constructs (a
  //    for-in header vs a statement run), so they share a stage.
  [
    DestructureForIn(enabled: options.destructureForIn),
    DestructureLocals(enabled: options.destructureLocals),
  ],

  // 8. Innermost edits, run last so they see final positions. abstract-final
  //    needs the whole project resolved to decide which classes are safe to seal.
  [
    DotShorthands(enabled: options.dotShorthands),
    StringInterpolation(enabled: options.stringInterpolation),
    NullAwareSpread(enabled: options.nullAwareSpread),
    NullAwareElements(enabled: options.nullAwareElements),
    AbstractFinalClasses(enabled: options.abstractFinalClasses),
  ],
];
