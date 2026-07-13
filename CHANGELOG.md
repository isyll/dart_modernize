# Changelog

## 0.7.3

- Dot shorthands now collapse a static member or method on a **generic** class.
  `WidgetStateProperty.resolveWith(...)` in a `WidgetStateProperty<Color?>?`
  context becomes `.resolveWith(...)`, and a static getter such as
  `WidgetStateProperty.none` becomes `.none`. A static member never uses the
  class's type arguments, so the collapse resolves against the same element the
  context type already names; previously every generic-owner static was left
  qualified.

## 0.7.2

- Dot shorthands now collapse a constant inside an object or record pattern
  field, matching it against the field's type:
  `NetworkException(kind: NetworkFailureKind.timeout)` becomes
  `NetworkException(kind: .timeout)`. Previously only a constant matched against
  the whole scrutinee collapsed.
- Dot shorthands now collapse a return whose type is the enclosing generic
  member's own type variable. Inside `Future<Result<T>> guarded<T>(...)`,
  `return Result.success(...)` becomes `return .success(...)`. The type-equality
  check treated `Result<T>` (context) and `Result<T>` (written) as different
  because both mention the type variable `T`, so such returns never collapsed.

## 0.7.1

- Dot shorthands now collapse inside a factory constructor's body. A `return`
  or `=>` that builds the class becomes a shorthand, so
  `factory AuthTokens.fromJson(...) { return AuthTokens(...); }` becomes
  `... { return .new(...); }`. The context is the constructor's own class type,
  matching the handling of function, method, and getter returns; a factory that
  returns a subtype is left qualified, since `.new()` would build the wrong type.

## 0.7.0

- Dot shorthands now collapse two patterns common to service-locator and
  dependency-injection code. An argument to a generic call fixed by an explicit
  `<...>` gets a real context, so `sl.registerSingleton<CrashReporter>(reporter
  ?? CrashReporter())` becomes `...(reporter ?? .new())`; and the body of a
  factory closure takes its context from the function type the closure is
  written against, so `sl.registerLazySingleton<ThemeCubit>(() =>
  ThemeCubit(storage: sl()))` becomes `...(() => .new(storage: sl()))`. Both are
  skipped when the type is still inferred from that very argument or closure (a
  generic call with no explicit `<...>`, such as `xs.map((x) => Foo(x))`), since
  collapsing would leave nothing to infer the type from.
- `abstract-final-classes` now recognizes a dot-shorthand `.new(...)` /
  `.named(...)` as instantiating its class, so a class the dot-shorthands pass
  reduced to `.new()` is no longer mislabelled `abstract final` (which would
  have made that `.new()` construct an abstract class).

## 0.6.3

- Dot shorthands now collapse a static member or enum value reached through an
  import prefix. A switch over an import-prefixed enum, such as
  `permission_handler.PermissionStatus.granted => PermissionResult.granted`,
  becomes `.granted => .granted`. Through a prefix a static access parses as a
  three-part property access (`(prefix.Type).member`) rather than the two-part
  form the pass already handled, so it was previously left qualified while the
  unprefixed side collapsed. Import-prefixed constructors and static methods
  (`prefix.Type(...)`, `prefix.Type.method(...)`) collapse the same way.

## 0.6.2

- Dot shorthands now collapse a default parameter value against the parameter's
  type. `Stream<T> watch({LocationAccuracy accuracy = LocationAccuracy.high})`
  becomes `Stream<T> watch({LocationAccuracy accuracy = .high})`. Named,
  optional-positional, and field/super formals (`this.x = ...`) are all covered;
  the parameter element's type is used, so a field formal whose type comes from
  its field still resolves.

## 0.6.1

- Dot shorthands now collapse a chain head on the **left** operand of `??`, not
  only the right. `ThemeMode.values.asNameMap()[saved] ?? ThemeMode.system` now
  becomes `.values.asNameMap()[saved] ?? .system`; previously only the right
  operand was shortened while the left kept its type name. Both operands take the
  `??` expression's context type (Dart infers the left in its nullable form, but
  the shorthand only needs the element), so a qualified chain on either side
  resolves against the same type.

## 0.6.0

- Dot shorthands now collapse the head of a selector chain, not just a
  standalone expression. When the whole chain's context type names the head's
  type, the leading `TypeName` is dropped and the trailing selectors are kept:
  `expiry.difference(DateTime.now().toUtc())` becomes
  `expiry.difference(.now().toUtc())`, `DateTime.tryParse(s)?.toUtc()` becomes
  `.tryParse(s)?.toUtc()`, and `Color.values.first` becomes `.values.first`. The
  context flows up through `.method(...)`, `.getter`, `[index]`, and `!`
  selectors to wherever the chain sits (argument, return, `switch` case, and
  every other position already supported). The head is left qualified when its
  referenced type differs from the chain's context (`int.parse(s).toDouble()` in
  a `num` context) or when the position has no context type (the left of `==`).

## 0.5.0

- Select transformations by naming them as positional arguments and drop the
  `--only` flag. `dart_modernize cascades inline-return` now runs just those two
  passes and skips the rest, replacing `--only cascades,inline-return`. Naming
  any pass turns every unnamed one off and overrides the individual
  `--<name>` flags, exactly as `--only` did; naming none still runs everything.
  A positional that is not a transformation name is the target path, so
  `dart_modernize lib/` and `dart_modernize lib/ cascades` both work, and an
  unrecognized name is rejected with a usage error listing the valid
  transformations. The individual `--no-<name>` toggles are unchanged.

## 0.4.1

- Fix `sort-members` and `sort-constructors-first` disagreeing about where
  constructors go. `sort-members` used to order fields before constructors while
  `sort-constructors-first` lifts constructors before every other member, so
  running one after the other on the same file flip-flopped it forever and the
  tool never settled (`--only sort-members` then `--only sort-constructors-first`
  each undid the other). `sort-members` now emits constructors first, matching
  the `sort_constructors_first` lint, so the two passes agree and each is a
  no-op on the other's output. A full default run is unaffected; only a
  standalone `--only sort-members` changes order.

## 0.4.0

- Add `--only`, an allow-list that runs just the transformation(s) you name and
  skips every other one. Repeat the flag or comma-separate names to select
  several (`--only cascades,inline-return`). When given, it overrides the
  individual `--<transformation>` flags, so a single pass no longer requires
  spelling out `--no-` for all the others. Unknown names are rejected with a
  usage error listing the valid transformations.

## 0.3.0

- Dot shorthands now collapse record fields. A positional field takes its
  context from the matching field of the record's type and a named field from
  the same-named field, so a list like
  `[(StockReadingType.opening, label, Icons.sunny), ...]` becomes
  `[(.opening, label, Icons.sunny), ...]`. When an untyped list of records has
  no element type to fall back on, the inferred record element type is hoisted
  onto the literal (`<(Foo, String)>[...]`) so the field shorthands have a
  context to resolve against. Hoisting happens only when every field of the
  record type is precise; a field typed `dynamic`, `Object`, `Null`, or an
  unresolved type variable leaves the record untouched.
- Dot shorthands also derive a context type through a `??` right-hand side
  (`maybe ?? Color.blue` becomes `maybe ?? .blue`) and a `yield` in a `sync*` or
  `async*` generator, matching the existing handling of returns and assignments.
- `--prefer-inferred-types` now drops a type annotation only when the
  initializer's type is obvious from the initializer (a literal, an
  explicitly-typed collection literal, a spelled-out constructor call, a cast, or
  a cascade or prefix over one of these), matching the analyzer's
  `omit_obvious_*` / `specify_nonobvious_*` rules. A non-obvious initializer such
  as a method call or property access keeps its annotation, so the pass no longer
  introduces a `specify_nonobvious_*` diagnostic that `dart fix` would revert
  (which made a `--no-fix-all` run disagree with a full run).
- Reject a project whose pubspec SDK constraint allows a Dart version older than
  3.12. The transformations emit 3.12+ idioms, so such a project would be broken
  by them; raise the constraint to `>=3.12.0 <4.0.0` before modernizing.

## 0.2.3

- Trim trailing whitespace from subprocess stderr in error messages (e.g. `dart fix`, `dart format` failures).

## 0.2.2

- No user-facing changes; removes duplicate test run from the release workflow.

## 0.2.1

- Fix README code example: use explicit `Set<Permission>` type annotation.

## 0.2.0

- Add `--sort-constructors-first` pass: moves every constructor before the other
  members of a class, enum, mixin, or extension type, satisfying the
  `sort_constructors_first` lint. Attached doc comments and annotations move with
  their constructor, and the pass runs after `--sort-members` so the two compose.
  Enabled by default; disable with `--no-sort-constructors-first`.

## 0.1.1

- Skip `build/` and other excluded or hidden directories while scanning, so the
  tool no longer crashes on deep build trees (notably on Windows).
- Keep a type annotation the initializer's dot shorthand needs (`final Foo x =
  .new(...)` is left alone instead of dropping `Foo`).
- Don't shorten an argument whose generic constructor infers its type from that
  argument, which would leave the shorthand without a context type.
- Don't add `abstract final` to a class that extends, implements, or mixes in
  another type (such as test mocks).

## 0.1.0

Initial release.

- Modernizes Dart and Flutter code with type-aware passes: dot shorthands,
  switch expressions, expression bodies, cascades, string interpolation,
  null-aware collections, inferred types, super parameters, private named
  parameters, primary constructors, and abstract final classes.
- Organizes imports, sorts members, applies `dart fix`, and formats the result.
- Preview every change with `--dry-run`; toggle any pass with `--no-<pass>`.
- Skips generated files and honors `analysis_options.yaml` excludes.
