import '../cli/options.dart';
import 'transformation.dart';
import 'transformations/abstract_final_classes.dart';
import 'transformations/cascades.dart';
import 'transformations/dot_shorthands.dart';
import 'transformations/expression_bodies.dart';
import 'transformations/final_locals.dart';
import 'transformations/inline_return.dart';
import 'transformations/fix_all.dart';
import 'transformations/null_aware_elements.dart';
import 'transformations/null_aware_spread.dart';
import 'transformations/organize_imports.dart';
import 'transformations/primary_constructors.dart';
import 'transformations/private_named_parameters.dart';
import 'transformations/sort_members.dart';
import 'transformations/string_interpolation.dart';
import 'transformations/super_parameters.dart';
import 'transformations/switch_expressions.dart';

export 'transformations/abstract_final_classes.dart';
export 'transformations/cascades.dart';
export 'transformations/dot_shorthands.dart';
export 'transformations/expression_bodies.dart';
export 'transformations/final_locals.dart';
export 'transformations/inline_return.dart';
export 'transformations/fix_all.dart';
export 'transformations/null_aware_elements.dart';
export 'transformations/null_aware_spread.dart';
export 'transformations/organize_imports.dart';
export 'transformations/primary_constructors.dart';
export 'transformations/private_named_parameters.dart';
export 'transformations/sort_members.dart';
export 'transformations/string_interpolation.dart';
export 'transformations/super_parameters.dart';
export 'transformations/switch_expressions.dart';

/// Returns the ordered list of transformations wired to [options].
///
/// The order matters: structural passes (dot shorthands, primary constructors,
/// switch expressions) run before cosmetic ones (imports, members) so
/// re-resolution sees clean code.  Cascades must precede FinalLocals so that
/// cascade edits (at stmt.offset) win over final-locals edits (also at
/// stmt.offset) via the stable-sort in EditCollector.
List<Transformation> buildTransformations(CliOptions options) => [
  DotShorthands(enabled: options.dotShorthands),
  PrivateNamedParameters(enabled: options.privateNamedParameters),
  PrimaryConstructors(enabled: options.primaryConstructors),
  SuperParameters(enabled: options.superParameters),
  SwitchExpressions(enabled: options.switchExpressions),
  Cascades(enabled: options.cascades),
  InlineReturn(enabled: options.inlineReturn),
  FinalLocals(enabled: options.finalLocals),
  ExpressionBodies(enabled: options.expressionBodies),
  StringInterpolation(enabled: options.stringInterpolation),
  NullAwareSpread(enabled: options.nullAwareSpread),
  NullAwareElements(enabled: options.nullAwareElements),
  OrganizeImports(enabled: options.organizeImports),
  SortMembers(enabled: options.sortMembers),
  FixAll(enabled: options.fixAll),
  AbstractFinalClasses(enabled: options.abstractFinalClasses),
];
