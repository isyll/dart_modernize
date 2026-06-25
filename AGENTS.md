# AGENTS.md

## What this is

`dart_modernize` is a Dart CLI tool that modernizes Dart and Flutter codebases.
It is **not a library**; the public surface is `bin/dart_modernize.dart`.

## Structure

```
bin/dart_modernize.dart              entry point: delegates to lib/
lib/
  dart_modernize.dart                barrel: re-exports lib/src/
  src/
    runner.dart                      CLI argument parsing and dispatch
    modernize_exception.dart         exception type
    cli/
      options.dart                   ArgParser + CliOptions
    analysis/
      project_analyzer.dart          full type resolution
      validator.dart                 pubspec / SDK validation
    engine/
      source_edit.dart               SourceEdit record (offset, length, replacement)
      edit_collector.dart            collects + applies edits, detects conflicts
      edit_diff.dart                 reduces a rewritten file to one SourceEdit
      file_filter.dart               generated-file exclusion (*.g.dart etc.)
      node_range.dart                declaration range incl. attached comments
      import_organizer.dart          sort / group / prune directives
      member_sorter.dart             reorder unit and class members
      unified_diff.dart              dry-run diff formatter
    pipeline/
      pipeline.dart                  ModernizePipeline orchestrator
      transformation.dart            Transformation interface
      transformations.dart           buildTransformations()
      safe_reference.dart            shared helper for the null-aware passes
      transformations/               one file per pass
test/
  cli/                               unit tests: options, flags, dry-run, idempotence
  e2e/                               end-to-end combined and robustness tests
  golden/                            one golden suite per transformation pass
  fixtures/                          fixture files consumed by golden suites
  support/                           shared harness (cli_harness, golden, triggers)
```

## Conventions

- Dart 3.12+. Null-safe. No legacy patterns.
- All logic lives in `lib/src/`. `bin/` only delegates.
- `package:args` for argument parsing, `package:path` for path operations.
- Strict analyzer: `strict-casts`, `strict-inference`, `strict-raw-types` are all on.
- `dart format`, `dart analyze --fatal-infos`, `dart test` must pass before every commit.
- NEVER add decorative comments.
- NEVER use em dashes (—).

## Commit rules: MANDATORY, no exceptions

- **Simple, plain message only.** No conventional commit prefixes (`fix:`, `feat:`, `ci:`, `chore:`, etc.).
- **No `Co-Authored-By`, no `Signed-off-by`, no trailer lines of any kind.** Never append AI attribution or tool metadata.
- **No body, no footer.** One short subject line, done.

Good: `quote help wanted label color`
Bad: `fix: quote help wanted label color to prevent YAML integer parsing` + `Co-Authored-By: ...`

## Working here

```sh
dart pub get                                  # install deps
dart run bin/dart_modernize.dart --help       # run locally
dart test                                     # run tests
dart format .                                 # format
dart analyze --fatal-infos                    # lint
```
