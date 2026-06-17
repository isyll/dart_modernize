# Copilot Instructions

- Dart 3.12+. Null safety required. Use modern idioms (records, patterns, etc.).
- All logic goes in `lib/src/`. `bin/dart_modernize.dart` only calls `run(args)`.
- Use `package:args` for argument parsing, `package:path` for path operations.
- Mirror `lib/src/` structure in `test/`: one test file per source file.
- Strict analyzer mode is on (`strict-casts`, `strict-inference`, `strict-raw-types`).
- No comments explaining what code does. Only add a comment for a non-obvious WHY.
- No co-authored-by or similar metadata in commits.
- Before suggesting code: mentally run `dart format` and `dart analyze --fatal-infos`.
