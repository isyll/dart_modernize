# Golden fixtures

Each sub-folder corresponds to one transformation pass and holds its golden
test cases. The reusable runner lives in
[`test/support/golden.dart`](../support/golden.dart) and the CLI harness that
actually runs the tool in [`test/support/cli_harness.dart`](../support/cli_harness.dart).

## Folder = feature

| Folder                      | CLI flag                     |
| --------------------------- | ---------------------------- |
| `dot_shorthands/`           | `--dot-shorthands`           |
| `private_named_parameters/` | `--private-named-parameters` |
| `primary_constructors/`     | `--primary-constructors`     |
| `switch_expressions/`       | `--switch-expressions`       |
| `organize_imports/`         | `--organize-imports`         |
| `sort_members/`             | `--sort-members`             |
| `fix_all/`                  | `--fix-all`                  |

## Pending features (spec-only, no flag yet)

These folders hold fixtures for transformations that are **specified but not yet
implemented or wired to a CLI flag**. Each still has a golden suite under
[`test/golden/`](../golden/), but because the feature has no pass, the runner
executes with every existing pass disabled (see `onlyFeatureArgs`): every input
is left byte-for-byte unchanged. The upshot is exactly the intended TDD state:

- `<case>.unchanged.dart` negatives **pass** (the tool already leaves them alone),
  and
- `<case>.input.dart` / `<case>.expected` positives **fail** until the pass is
  built. The failing assertion names the fixture and its expected output, so the
  fixtures are the spec the implementation must satisfy.

| Folder                   | Transformation                                  |
| ------------------------ | ----------------------------------------------- |
| `null_aware_elements/`   | `if (x != null) x` → `?x` (single-eval guarded) |
| `null_aware_spread/`     | `if (l != null) ...l` → `...?l`                 |
| `cascades/`              | repeated member writes → `..` cascade           |
| `super_parameters/`      | forwarded params → `super.x`                    |
| `expression_bodies/`     | single-`return` block bodies → `=>`             |
| `string_interpolation/`  | `'a ' + b` concat chains → `'a $b'`             |

When a pass is implemented, add its `--flag` to `buildArgParser`, register it in
`featureFlags`/`allFeatures` (with a trigger), and move its row into the table
above; the same fixtures then verify the real pass in isolation.

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
