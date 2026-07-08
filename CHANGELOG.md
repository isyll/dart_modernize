# Changelog

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
