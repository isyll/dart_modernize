# Pass ordering and stages

This note describes how `dart_modernize` orders its transformation passes. It is
the written companion to
[`test/cli/pipeline_order_test.dart`](../test/cli/pipeline_order_test.dart) and
[`test/e2e/interaction_test.dart`](../test/e2e/interaction_test.dart).

## Stages

The transform stage runs as a fixed sequence of pass groups. Each group is
resolved once and applied before the next group runs, so a pass always reads the
finished output of the groups before it.

`buildTransformationStages` in
[`lib/src/pipeline/transformations.dart`](../lib/src/pipeline/transformations.dart)
is the single source of the layering. The pipeline only filters each stage by
`enabled`; it never reorders.

| Stage | Passes | Role |
| ----- | ------ | ---- |
| 1 | `primary-constructors` | Outermost class rewrite. |
| 2 | `switch-expressions`, `cascades`, `super-parameters`, `private-named-parameters` | Fold statement runs, build new constructs. |
| 3 | `inline-return`, `prefer-inferred-types` | Read stage 2. |
| 4 | `expression-bodies`, `final-locals` | Read stage 3. |
| 5 | `dot-shorthands`, `string-interpolation`, `null-aware-spread`, `null-aware-elements`, `abstract-final-classes` | Innermost edits and the project-wide seal. |

Two rules decide a pass's stage:

1. **A pass that builds on another pass's output runs in a later stage.** The
   longest such chain is `cascades -> inline-return -> expression-bodies ->
   dot-shorthands`:

   ```dart
   Conn build(String t) {
     var c = Conn();   // stage 2 cascades        -> var c = Conn()..open()..send(t); return c;
     c.open();         // stage 3 inline-return    -> return Conn()..open()..send(t);
     c.send(t);        // stage 4 expression-bodies -> Conn build(String t) => Conn()..open()..send(t);
     return c;
   }
   ```

2. **A pass that rewrites a whole span runs before the passes that edit inside
   it.** `primary-constructors` copies a class's other members, and `cascades`,
   the switch rewrite, and the partial super-forward copy their inner
   expressions. Running `dot-shorthands`, `string-interpolation`, and the
   null-aware passes last lets them edit the final positions.

`prefer-inferred-types` (stage 3) runs before `dot-shorthands` (stage 5). When a
declared type is redundant, prefer-inferred-types drops it, so dot-shorthands
sees no context type and leaves the value alone: `final c = Color.blue` and
`final p = Provider()`, not `final Color c = .blue` or `final Provider p = .new()`.

Passes in the same stage touch separate parts of the code, so their order within
a stage does not matter.

## Execution

```
for each stage:
    apply the previous stage's edits, re-resolving changed files
    for each non-generated file:
        collector = EditCollector()
        for each enabled pass in this stage:
            collector.addAll(pass.editsFor(unit))
        stage collector.apply(original) in memory
write the final in-memory content to disk
```

Every stage re-resolves the project, but the analyzer serves unchanged files
from cache, so only files an earlier stage touched are re-analyzed.

Within a stage, every pass computes its edits against the same source, and
nothing is written until all passes in the stage have contributed. `EditCollector`
sorts the edits by offset, drops overlaps, and applies the rest in one
left-to-right walk
([`engine/edit_collector.dart`](../lib/src/engine/edit_collector.dart)). Because
the passes in a stage target separate regions, no overlap is dropped in practice.

## Finalize

After the structural stages, the finalize passes run over the files on disk, in
a fixed order (`buildFinalizeTransformations`):

1. `dart fix --apply` first, because its fixes may remove imports.
2. `organize-imports` (with `sort-members`, computed on one source and merged).
3. `dart format` last, over the same filtered file list the rest of the pipeline
   uses, since it does not read `analyzer: exclude:` or `--exclude` itself.
