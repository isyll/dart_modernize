# Golden fixtures

Each sub-folder corresponds to one transformation pass and holds its golden
test cases. The reusable runner lives in
[`test/support/golden.dart`](../support/golden.dart) and the CLI harness that
actually runs the tool in [`test/support/cli_harness.dart`](../support/cli_harness.dart).

## Folder = feature

All seventeen transformation passes have a fixtures folder and a CLI flag.
Each pass has full visitor logic; running the tool with only that flag enabled
rewrites positive fixtures as expected and leaves negative (`.unchanged.dart`)
fixtures byte-for-byte identical.

| Folder                        | CLI flag                       |
| ----------------------------- | ------------------------------ |
| `dot_shorthands/`             | `--dot-shorthands`             |
| `private_named_parameters/`   | `--private-named-parameters`   |
| `primary_constructors/`       | `--primary-constructors`       |
| `super_parameters/`           | `--super-parameters`           |
| `switch_expressions/`         | `--switch-expressions`         |
| `cascades/`                   | `--cascades`                   |
| `inline_return/`              | `--inline-return`              |
| `final_locals/`               | `--final-locals`               |
| `expression_bodies/`          | `--expression-bodies`          |
| `string_interpolation/`       | `--string-interpolation`       |
| `null_aware_spread/`          | `--null-aware-spread`          |
| `null_aware_elements/`        | `--null-aware-elements`        |
| `organize_imports/`           | `--organize-imports`           |
| `sort_members/`               | `--sort-members`               |
| `fix_all/`                    | `--fix-all`                    |
| `abstract_final_classes/`     | `--abstract-final-classes`     |

## Adding a case = adding files (no code)

A case is one of:

- **Positive**: a pair of files:
  - `<case>.input.dart`: the source the tool is run over. It is the "before"
    code, so it is always valid current-syntax Dart and keeps the `.dart`
    extension (editor highlighting, format-clean).
  - `<case>.expected`: the exact source the file must contain afterwards. It
    deliberately **drops** the `.dart` extension so Dart tooling treats it as
    plain data: `dart format` and `dart analyze` skip it, which lets it hold
    output using language features newer than this package's version (e.g.
    primary constructors, which `dart format` cannot yet parse here).

- **Negative**: a single file:
  - `<case>.unchanged.dart`: the transformation must **not** apply here, so the
    expected output is the input itself. One file, no duplicated content.

The runner drops every input into one throwaway package, runs the real CLI once
with only that feature's pass enabled, and compares each file to its expected
text. Each case becomes its own `test()`, named after the file stem.

Because every case is its own library file (no cross-imports), top-level names
may repeat freely between cases.

## Optional per-feature project files

If a feature folder contains a `pubspec.yaml` or `analysis_options.yaml`, it is
used for that feature's throwaway project instead of the defaults. This is how
`primary_constructors/` opts into a higher SDK language version, and how
lint-driven passes enable the lints they fix.

## What "expected" encodes

Expected files are written as the tool's final, `dart format`-clean output, so
they stay valid once the finalize step formats results. Keep them idempotent:
running the tool on an expected file must produce no further changes.
