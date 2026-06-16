import '../cli/options.dart';
import 'transformation.dart';
import 'transformations/dot_shorthands.dart';
import 'transformations/fix_all.dart';
import 'transformations/organize_imports.dart';
import 'transformations/primary_constructors.dart';
import 'transformations/private_named_parameters.dart';
import 'transformations/sort_members.dart';

export 'transformations/dot_shorthands.dart';
export 'transformations/fix_all.dart';
export 'transformations/organize_imports.dart';
export 'transformations/primary_constructors.dart';
export 'transformations/private_named_parameters.dart';
export 'transformations/sort_members.dart';

/// Returns the ordered list of transformations wired to [options].
///
/// The order matters: structural passes (dot shorthands, primary constructors)
/// run before cosmetic ones (imports, members) so re-resolution sees clean code.
List<Transformation> buildTransformations(CliOptions options) => [
  DotShorthands(enabled: options.dotShorthands),
  PrivateNamedParameters(enabled: options.privateNamedParameters),
  PrimaryConstructors(enabled: options.primaryConstructors),
  OrganizeImports(enabled: options.organizeImports),
  SortMembers(enabled: options.sortMembers),
  FixAll(enabled: options.fixAll),
];
