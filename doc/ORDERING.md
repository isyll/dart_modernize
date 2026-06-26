# Pass ordering, offset safety, and re-resolution

This note documents how `dart_modernize` sequences its transformation passes,
why the order is what it is, and how the transform stage repeats until the
project stops changing. It is the written rationale referenced by
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
7. `inline-return`
8. `final-locals`
9. `prefer-inferred-types`
10. `expression-bodies`
11. `string-interpolation`
12. `null-aware-spread`
13. `null-aware-elements`
14. `organize-imports`
15. `sort-members`
16. `fix-all`
17. `abstract-final-classes`

The grouping is **structural rewrites first, cosmetic passes next, bulk fixes
last**: passes that change the shape of declarations and statements (1–13) run
ahead of the ones that reorder or reformat whole files (`organize-imports`,
`sort-members`) and the catch-all `fix-all`. `abstract-final-classes` is placed
last because it requires a full project-wide analysis pass to determine which
classes are safe to seal before it can emit any edits. That grouping is asserted
as an invariant by the order test, so a reordering that breaks it fails CI.

`cascades` (6) must precede both `inline-return` (7) and `final-locals` (8).
When a cascade run targets a `var` declaration that is also immediately returned,
cascades folds the writes first (producing `var x = X()..a..b; return x;`), and
`inline-return` then collapses that to `return X()..a..b;` on the next run.
Within a single run, `inline-return` (7) must precede `final-locals` (8): both
can emit an edit at `stmt.offset` when a `var` declaration is immediately
returned -- the inline-return edit replaces the entire declaration-plus-return;
the final-locals edit replaces only the `var` keyword. Insertion order breaks the
tie (stable sort), so inline-return wins and the final-locals edit is silently
discarded as an overlap, converging in one run.

## The execution model (verified)

The transform stage repeats until the project stops changing
([`lib/src/pipeline/pipeline.dart`](../lib/src/pipeline/pipeline.dart)):

```
repeat (up to a safety cap):
    for each non-generated file (re-resolved from the in-memory copy):
        collector = EditCollector()
        for each enabled pass (in the order above):
            collector.addAll(pass.editsFor(unit))   // every pass sees the SAME unit
        stage collector.apply(original) in memory
    stop when no file changed this round
write the final in-memory content to disk
```

Within a single round, two properties hold, and both are what the tests pin:

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
order" and end-to-end by the interaction suite, where several passes edit one
file and all of them land correctly.

### Overlap resolution: earliest offset wins, deterministically

When two edits overlap, `_deoverlap` keeps the one with the earlier offset and
drops the other. The dropped edit is never mis-applied; the output is always
valid source. Pass order therefore affects the final bytes **only** when two
passes emit edits at the _exact same_ offset (a tie), which is rare in practice;
distinct passes target distinct syntactic positions.

## Re-resolution: between rounds, to a fixpoint

There is no re-resolution between passes _within_ a round: all passes in a round
run against the one AST captured for each file, so a later pass cannot see an
earlier pass's edit until the next round. The pipeline closes that gap by
re-resolving the staged in-memory content and running the passes again, repeating
until a round makes no change.

This is what lets passes that build on each other compose in a single
invocation. When two passes target **overlapping spans of the same construct**,
the overlap rule drops one edit for that round; the dropped edit simply applies
on the next round once the construct has settled into a shape it no longer
overlaps. For example:

| Construct                                                     | Passes that collide                          |
| ------------------------------------------------------------- | -------------------------------------------- |
| `T f() { return T.x; }`                                       | `expression-bodies` + `dot-shorthands`       |
| `String f() { return a + b; }`                                | `expression-bodies` + `string-interpolation` |
| `C({required int x}) : super(a: A.x, x: x)` (partial forward) | `super-parameters` + `dot-shorthands`        |
| `var p = X(); p.a(); p.b(); return p;`                        | `cascades` + `inline-return`                 |
| `T x = e;` (bare-typed local, later read)                     | `prefer-inferred-types` + `final-locals`     |

The "passes compose to a fixpoint in one run" group in the interaction suite
runs each of these through the CLI once and asserts it reaches the fully
modernized form, then that a second run changes nothing.

### Cost and the safety cap

Each round re-resolves the project, so a file that needs several rounds is
resolved several times. Real projects settle in a handful of rounds; the loop is
bounded by a safety cap (`_maxRounds`) so a misbehaving pass can never spin
forever.
