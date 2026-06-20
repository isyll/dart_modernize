# Pass ordering, offset safety, and re-resolution

This note documents how `dart_modernize` sequences its transformation passes,
why the order is what it is, and the one consequence that order does **not**
buy us today. It is the written rationale referenced by
[`test/cli/pipeline_order_test.dart`](../test/cli/pipeline_order_test.dart) and
[`test/e2e/interaction_test.dart`](../test/e2e/interaction_test.dart).

## The fixed order

`buildTransformations` in
[`lib/src/pipeline/transformations.dart`](../lib/src/pipeline/transformations.dart)
is the single source of pass order. The pipeline only ever _filters_ that list
by `enabled`; it never reorders. The order is:

1. `dot-shorthands`
2. `private-named-parameters`
3. `primary-constructors`
4. `super-parameters`
5. `switch-expressions`
6. `cascades`
7. `expression-bodies`
8. `string-interpolation`
9. `null-aware-spread`
10. `null-aware-elements`
11. `organize-imports`
12. `sort-members`
13. `fix-all`

The grouping is **structural rewrites first, cosmetic passes next, bulk fixes
last**: passes that change the shape of declarations and statements (1–10) run
ahead of the ones that reorder or reformat whole files (`organize-imports`,
`sort-members`) and the catch-all `fix-all`. That grouping is asserted as an
invariant by the order test, so a reordering that breaks it fails CI.

## The execution model (verified)

For each non-generated file the pipeline does exactly this
([`lib/src/pipeline/pipeline.dart`](../lib/src/pipeline/pipeline.dart)):

```
resolve the file once                 // ProjectAnalyzer, one ResolvedUnitResult
collector = EditCollector()
for each enabled pass (in the order above):
    collector.addAll(pass.editsFor(unit))   // every pass sees the SAME unit
modified = collector.apply(original)         // applied once
write(modified)
```

Two properties follow directly, and both are what the tests pin:

### Offset safety: one pass never invalidates another's offsets

Every pass computes its edit offsets against the **same original source**, and
nothing is written until **all** passes have contributed. `EditCollector` then
sorts the edits by offset, drops overlaps (see below), and applies the survivors
in a single left-to-right walk that consumes the original string by original
coordinates ([`engine/edit_collector.dart`](../lib/src/engine/edit_collector.dart)).
Because application never mutates the buffer the offsets refer to, an edit
produced by pass A can never shift or invalidate an offset produced by pass B.
Insertion order is irrelevant for non-overlapping edits, proven by
`EditCollector` "applies multiple non-overlapping edits regardless of insertion
order" and end-to-end by the interaction suite's "compose cleanly" group, where
three passes edit one file and all three land correctly.

### Overlap resolution: earliest offset wins, deterministically

When two edits overlap, `_deoverlap` keeps the one with the earlier offset and
drops the other. The dropped edit is never mis-applied; the output is always
valid source. Pass order therefore affects the final bytes **only** when two
passes emit edits at the _exact same_ offset (a tie), which is rare in practice;
distinct passes target distinct syntactic positions.

## Re-resolution: there is none between passes

There is **no re-resolution between passes within a run**. All passes run
against the one AST captured at the top of the loop. A consequence worth stating
plainly: a later pass in the list cannot consume an earlier pass's _AST change_
during the same run, because it never sees it; it sees the original tree. The
order above is thus a tie-break and a statement of intent, not a data dependency
the current implementation exploits. Passes are assumed to operate on
**independent constructs**.

## The one thing the order does not buy us: single-run idempotence on overlaps

When two passes target **overlapping spans of the same construct**, one edit is
dropped per the overlap rule and only applies on the _next_ run. The tool still
**converges** to the correct, fully-modernized form; it is just not single-run
idempotent for those constructs. This happens because several passes emit a
replacement that _spans and re-emits_ an inner expression verbatim, and that
span hides another pass's edit nested inside it:

| Construct                                                     | Passes that collide                          | Converges in |
| ------------------------------------------------------------- | -------------------------------------------- | ------------ |
| `T f() { return T.x; }`                                       | `expression-bodies` + `dot-shorthands`       | 2 runs       |
| `String f() { return a + b; }`                                | `expression-bodies` + `string-interpolation` | 2 runs       |
| `C({required int x}) : super(a: A.x, x: x)` (partial forward) | `super-parameters` + `dot-shorthands`        | 2 runs       |
| `p.add(A.x)` inside a folded cascade run                      | `cascades` + `dot-shorthands`                | 2 runs       |

The "converge across runs" group in the interaction suite reproduces all four
and asserts each reaches the correct fixpoint. The existing golden and combined
fixtures sidestep the issue by keeping such constructs already in their target
shape (e.g. methods already written as `=>` bodies), which is why single-run
idempotence holds for them.

### Why this is acceptable today, and how to remove it

It is acceptable because the output is always **valid** and the tool
**converges**; re-running is safe and cheap. Removing it (making overlapping
constructs converge in a single run) requires the pipeline to either
**re-resolve between passes** or **iterate the per-file transform to a
fixpoint**. Both are behavioural changes to the pipeline beyond this
consolidation pass and are flagged for review rather than made here.
