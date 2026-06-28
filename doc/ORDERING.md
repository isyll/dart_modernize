# Pass ordering, staging, and offset safety

This note documents how `dart_modernize` sequences its transformation passes and
why the transform stage is a **fixed, dependency-ordered pipeline** rather than
a loop that re-runs until the project stops changing. It is the written
rationale referenced by
[`test/cli/pipeline_order_test.dart`](../test/cli/pipeline_order_test.dart) and
[`test/e2e/interaction_test.dart`](../test/e2e/interaction_test.dart).

## Why a single deterministic pipeline

Some passes only become applicable after another pass has rewritten the code:
dot-shorthands collapses the value arms of a switch expression that
switch-expressions just produced; inline-return collapses a cascade that
cascades just folded. An earlier design re-ran every pass over the whole project
repeatedly until a round made no change, capped by a magic round limit.

That "repeat until convergence" loop is replaced by a fixed sequence of stages.
The passes form a small dependency DAG; grouping them into topological layers
lets each pass run **exactly once**, in a known stage, and still see the fully
applied output of everything it depends on. The number of stages is a
compile-time constant, so a single invocation is deterministic, bounded, and
needs no convergence check or safety cap.

## The stages

`buildTransformationStages` in
[`lib/src/pipeline/transformations.dart`](../lib/src/pipeline/transformations.dart)
is the single source of the layering. The pipeline only filters each stage by
`enabled`; it never reorders.

| Stage | Passes | Role |
| ----- | ------ | ---- |
| 1 | `primary-constructors` | Outermost class restructuring, alone. |
| 2 | `switch-expressions`, `cascades`, `super-parameters`, `private-named-parameters` | Structural producers: fold runs, synthesize new constructs. |
| 3 | `inline-return`, `prefer-inferred-types` | Consume stage 2. |
| 4 | `expression-bodies`, `final-locals` | Consume stage 3. |
| 5 | `dot-shorthands`, `string-interpolation`, `null-aware-spread`, `null-aware-elements`, `abstract-final-classes` | Innermost edits and the project-wide seal. |

Two rules fix this layering:

1. **Producer before consumer.** A pass that consumes a construct another pass
   produces runs in a strictly later stage. The longest such chain is
   `cascades -> inline-return -> expression-bodies -> dot-shorthands`:

   ```dart
   Conn build(String t) {
     var c = Conn();   // stage 2 cascades       -> var c = Conn()..open()..send(t); return c;
     c.open();         // stage 3 inline-return   -> return Conn()..open()..send(t);
     c.send(t);        // stage 4 expression-bodies-> Conn build(String t) => Conn()..open()..send(t);
     return c;
   }
   ```

2. **Container before content.** A pass that copies a span verbatim
   (primary-constructors copies retained members; cascades, the switch rewrite,
   and the partial super-forward copy their inner expressions) runs before the
   passes that edit inside that span, so a container rewrite never discards an
   inner edit. This is why `dot-shorthands`, `string-interpolation`, and the
   null-aware passes are last: by stage 5 every container has settled and the
   inner positions are final.

A consequence of rule 1 worth calling out: `prefer-inferred-types` (stage 3)
runs before `dot-shorthands` (stage 5). When a declared type is redundant,
prefer-inferred-types drops it, so dot-shorthands then sees no context type and
leaves the value alone. That is deliberate: `final c = Color.blue` is preferred
over `final Color c = .blue`, and `final p = Provider()` over
`final Provider p = .new()`. Dropping the type wins over introducing a shorthand.

Passes **within** one stage are mutually independent: they target disjoint
syntactic regions (different declarations, or different parts of one
declaration), so their relative order never changes the result.

## The execution model

The transform stage ([`lib/src/pipeline/pipeline.dart`](../lib/src/pipeline/pipeline.dart)):

```
for each stage (fixed order, no loop):
    apply the previous stage's staged edits, re-resolving changed files
    for each non-generated file (resolved from the in-memory copy):
        collector = EditCollector()
        for each enabled pass in this stage:
            collector.addAll(pass.editsFor(unit))   // passes see the SAME unit
        stage collector.apply(original) in memory
write the final in-memory content to disk
```

Every stage re-resolves the whole project, but the analyzer serves unchanged
files from cache, so only files an earlier stage actually touched are
re-analyzed. The cost is therefore close to one full resolution plus the
re-resolution of the (usually small) set of changed files, while the output is
fully deterministic.

### Offset safety: one pass never invalidates another's offsets

Within a stage, every pass computes its edit offsets against the **same** source,
and nothing is written until all passes in the stage have contributed.
`EditCollector` sorts the edits by offset, drops overlaps, and applies the
survivors in a single left-to-right walk over the original string
([`engine/edit_collector.dart`](../lib/src/engine/edit_collector.dart)). Because
application never mutates the buffer the offsets refer to, an edit from pass A
can never shift an offset from pass B. And because the passes in a stage target
disjoint regions, no overlap is dropped within a stage in practice.

## The finalize stage

After the structural stages settle, the finalize passes run over the files on
disk, in a fixed order (`buildFinalizeTransformations`):

1. `dart fix --apply` first, because its fixes may remove imports.
2. `organize-imports` (+ `sort-members`, computed on one source and merged).
3. `dart format` last, over the filtered file list (it does not honour
   `analyzer: exclude:` or `--exclude`, so it must be handed the same file set
   the rest of the pipeline uses, or it would reformat excluded files).
