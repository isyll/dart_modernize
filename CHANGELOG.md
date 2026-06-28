# Changelog

## 0.1.0

Initial release.

- Modernizes Dart and Flutter code with type-aware passes: dot shorthands,
  switch expressions, expression bodies, cascades, string interpolation,
  null-aware collections, inferred types, super parameters, private named
  parameters, primary constructors, and abstract final classes.
- Organizes imports, sorts members, applies `dart fix`, and formats the result.
- Preview every change with `--dry-run`; toggle any pass with `--no-<pass>`.
- Skips generated files and honors `analysis_options.yaml` excludes.
