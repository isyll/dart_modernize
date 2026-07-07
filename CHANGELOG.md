# Changelog

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
