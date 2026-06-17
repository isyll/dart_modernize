# AGENTS.md

## What this is

`dart_modernize` is a Dart CLI tool that modernizes Dart and Flutter codebases.
It is **not a library**; the public surface is `bin/dart_modernize.dart`.

## Structure

```
bin/dart_modernize.dart      entry point: calls run() from lib/, nothing else
lib/
  dart_modernize.dart        barrel: re-exports lib/src/
  src/
    runner.dart              CLI argument parsing and dispatch
test/                        mirrors lib/src/ structure
```

## Conventions

- Dart 3.12+. Null-safe. No legacy patterns.
- All logic lives in `lib/src/`. `bin/` only delegates.
- `package:args` for argument parsing, `package:path` for path operations.
- Strict analyzer: `strict-casts`, `strict-inference`, `strict-raw-types` are all on.
- `dart format`, `dart analyze --fatal-infos`, `dart test` must pass before every commit.

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
