import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/element/element.dart';

/// How [element] can be written as a type name in [unit]'s library, or null
/// when no name in scope reaches it.
///
/// A pass that writes a type the source only inferred (`final TripStop(:town)`
/// for a loop over `trip.stops`) cannot assume the bare name works: the type
/// may not be imported at all, may be imported with a prefix (`dap.Scope`),
/// hidden, shadowed by another import of the same name, or private to another
/// library. The name is looked up in the library's own scope first, then
/// through each import prefix. A deferred prefix is skipped, since its types
/// cannot be used in a pattern before the library is loaded.
String? typeNameInScope(ResolvedUnitResult unit, InterfaceElement element) {
  final name = element.name;
  if (name == null || name.isEmpty) return null;

  final fragment = unit.libraryFragment;
  if (fragment.scope.lookup(name).getter == element) return name;

  for (final prefix in fragment.prefixes) {
    if (prefix.fragments.any((f) => f.isDeferred)) continue;
    if (prefix.scope.lookup(name).getter == element) {
      return '${prefix.name}.$name';
    }
  }
  return null;
}
