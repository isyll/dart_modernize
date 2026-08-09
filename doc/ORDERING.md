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

Selecting a subset of passes (with `--only`, or turning some off with
`--no-<name>`) only flips each pass's `enabled` flag. The stage sequence is
unchanged, so a selected pass always runs in its stage's position no matter the
order it is named on the command line: `dart_modernize --only
inline-return,cascades` still runs `cascades` (stage 2) before `inline-return`
(stage 3).

| Stage | Passes | Role |
| ----- | ------ | ---- |
| 1 | `primary-constructors` | Outermost class rewrite. |
| 2 | `switch-expressions`, `cascades`, `super-parameters`, `private-named-parameters` | Fold statement runs, build new constructs. |
| 3 | `inline-return`, `prefer-inferred-types` | Read stage 2. |
| 4 | `expression-bodies`, `final-locals` | Read stage 3. |
| 5 | `null-aware-conditionals` | Replace a whole conditional expression. |
| 6 | `destructure-for-in` | Rewrite a loop header and its field reads. |
| 7 | `dot-shorthands`, `string-interpolation`, `null-aware-spread`, `null-aware-elements`, `abstract-final-classes` | Innermost edits and the project-wide seal. |

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

`prefer-inferred-types` (stage 3) runs before `dot-shorthands` (stage 7). When a
declared type is redundant, prefer-inferred-types drops it, so dot-shorthands
sees no context type and leaves the value alone: `final c = Color.blue` and
`final p = Provider()`, not `final Color c = .blue` or `final Provider p = .new()`.

`null-aware-conditionals` gets a stage of its own for the same reason, and it is
pinned on both sides. It replaces the entire conditional expression, so it has to
run *after* the passes that rewrite an enclosing statement (`inline-return`,
`expression-bodies`) have moved that conditional into its final home, and
*before* the innermost passes edit inside it, since a fallback arm is itself
rewritable: `box != null ? box.name : Color.red` becomes `box?.name ?? Color.red`
in stage 5 and then `box?.name ?? .red` in stage 7. Sharing a stage with either
neighbour would put two edits on overlapping spans, and `EditCollector` drops the
loser.

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
2. `organize-imports` (merged with `sort-members` when it is on, computed on
   one source; `sort-members` is off by default, so usually only
   `organize-imports` runs here).
3. `dart format` last, over the same filtered file list the rest of the pipeline
   uses, since it does not read `analyzer: exclude:` or `--exclude` itself.

## Rewrites vs reordering

The finalize phase is also where the two *layout-only* passes live, and the
distinction matters when reading a diff.

Every structural pass in the stage table rewrites a construct in place: it edits
the code it targets and leaves the surrounding declarations where they sit.
`sort-members` and `sort-constructors-first` do the opposite. They edit nothing
and move whole declarations, so their output is pure relocation.

That is safe because Dart does not resolve declarations positionally, so moving
one cannot change what a name resolves to. The single position-dependent thing is
field initialization order, which `MemberSorter` preserves explicitly: fields
share one priority slot and compare by source offset (see `_sortedMembers`), so
they move as a group but never past one another.

The cost is review noise, not correctness: a reordered file is a wall of moved
lines that buries any real change and misattributes `git blame`. That is why
`sort-members` is off by default (see `defaultOffTransformations`), and why it is
worth running on its own rather than in the same commit as a rewrite.

Both passes order class members, so they must agree with each other or the
pipeline would not converge. `pass_convergence_test.dart` guards that from two
sides: it runs them in either order and requires the same fixed point, and it
runs the full pipeline with `sort-members` switched on and then re-runs every
region-rewriting pass, which must be a no-op.
