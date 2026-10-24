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
(stage 4).

| Stage | Passes | Role |
| ----- | ------ | ---- |
| 1 | `collection-elements` | Fold an add/addAll run into one literal. |
| 2 | `switch-expressions`, `cascades`, `super-parameters`, `private-named-parameters` | Fold statement runs, build new constructs. |
| 3 | `primary-constructors` | Promote a class or an enum, once its members have settled. |
| 4 | `inline-return`, `prefer-inferred-types`, `future-pause`, `null-aware-calls`, `unmodifiable-of` | Read stage 3, rewrite statements stage 5 arrows. |
| 5 | `expression-bodies`, `final-locals` | Read stage 4. |
| 6 | `null-aware-conditionals` | Replace a whole conditional expression. |
| 7 | `destructure-for-in`, `destructure-locals` | Move field reads into a pattern. |
| 8 | `dot-shorthands`, `string-interpolation`, `null-aware-spread`, `null-aware-elements`, `abstract-final-classes`, `constructor-shorthands`, `empty-bodies`, `wildcard-parameters` | Innermost edits, declaration headers, and the project-wide seal. |

Two rules decide a pass's stage:

1. **A pass that builds on another pass's output runs in a later stage.** The
   longest such chain is `cascades -> inline-return -> expression-bodies ->
   dot-shorthands`:

   ```dart
   Conn build(String t) {
     var c = Conn();   // stage 2 cascades         -> var c = Conn()..open()..send(t); return c;
     c.open();         // stage 4 inline-return     -> return Conn()..open()..send(t);
     c.send(t);        // stage 5 expression-bodies -> Conn build(String t) => Conn()..open()..send(t);
     return c;
   }
   ```

2. **A pass that rewrites a whole span runs before the passes that edit inside
   it.** `cascades`, the switch rewrite, and the partial super-forward all copy
   their inner expressions. Running `dot-shorthands`, `string-interpolation` and
   the null-aware passes last lets them edit the final positions.

`primary-constructors` sits behind `private-named-parameters` for rule 1.
`Config({required int r}) : _r = r` is not promotable, but the
`Config({required this._r})` that private-named-parameters produces is. With the
promotion first, that class would only collapse on a second run, and the tool
would not be idempotent. `pass_convergence_test.dart` and `idempotence_test.dart`
both cover this.

`constructor-shorthands` and `empty-bodies` sit in stage 8, after
`primary-constructors`. The promotion copies the members it keeps as written,
factories included, so the shorthand rewrite of a retained `factory C.parse`
has to come later; and a class the promotion empties already ends in `;`.
Neither touches what the other passes in stage 8 edit: one rewrites a
constructor's name, the other the braces of an empty body.

`future-pause` and `null-aware-calls` join stage 4 so that `expression-bodies`
(stage 5) can arrow what they produce, as in `void dispose() =>
controller?.dispose();`. `null-aware-calls` also has to come before
`null-aware-conditionals` (stage 6): both can edit inside the same `if`, and
overlapping edits in one stage would be dropped. `future-pause` comes before
`dot-shorthands`, which would otherwise shorten the same call to
`.delayed(...)` first.

`prefer-inferred-types` (stage 4) runs before `dot-shorthands` (stage 8). When a
declared type is redundant, prefer-inferred-types drops it, so dot-shorthands
sees no context type and leaves the value alone: `final c = Color.blue` and
`final p = Provider()`, not `final Color c = .blue` or `final Provider p = .new()`.

`null-aware-conditionals` gets a stage of its own for the same reason, and it is
pinned on both sides. It replaces the entire conditional expression, so it has to
run *after* the passes that rewrite an enclosing statement (`inline-return`,
`expression-bodies`) have moved that conditional into its final home, and
*before* the innermost passes edit inside it, since a fallback arm is itself
rewritable: `box != null ? box.name : Color.red` becomes `box?.name ?? Color.red`
in stage 6 and then `box?.name ?? .red` in stage 8. Sharing a stage with either
neighbour would put two edits on overlapping spans, and `EditCollector` drops the
loser.

Passes in the same stage touch separate parts of the code, so their order within
a stage does not matter.

## Execution

```
for each stage:
    apply the previous stage's edits
    for each library, resolved once with all of its parts:
        record each unit's errors
        skip it if it is generated, excluded, or pinned below Dart 3.13
        for each enabled pass in this stage:
            keep the pass's edits for that unit
        stage the edits of every pass in memory
    with --verify: compare every file's errors with the recorded ones, and
        take back the edits behind any new error (see below)
write the final in-memory content to disk
```

A library is resolved once per stage and all of its units are visited
together, so a model with generated `part` files is not resolved again for
each part. A library pinned to an older language version (`// @dart = 2.12`)
is left as it is: the passes write Dart 3.13 syntax it cannot use. A library
whose resolution overflows the stack (a generated `operator ==` chaining
hundreds of `&&` can do it under the JIT) is skipped and reported, instead of
taking the run down.

Within a stage, every pass computes its edits against the same source, and
nothing is written until all passes in the stage have contributed. `EditCollector`
sorts the edits by offset, drops overlaps, and applies the rest in one
left-to-right walk
([`engine/edit_collector.dart`](../lib/src/engine/edit_collector.dart)). Because
the passes in a stage target separate regions, no overlap is dropped in practice.

### Checking each stage

With `--verify` (the default), the errors of every file are compared before and
after each stage, in memory, using the analyzer's cache so a file whose
dependencies did not change is not analyzed again
([`pipeline/stage_runner.dart`](../lib/src/pipeline/stage_runner.dart)). When a
stage adds an error:

1. If the broken file was edited in this stage, its edits are taken back.
2. Otherwise the error is in a caller, so the edits of the changed files it
   depends on are taken back: the ones it imports directly (following
   re-exports) first, then the ones it reaches through other files
   ([`engine/import_graph.dart`](../lib/src/engine/import_graph.dart)).
3. The check repeats, up to four rounds.
4. A file several passes edited then gets its passes back one at a time, and
   keeps the ones that leave the project error-free.

The passes taken back are reported as held back. This catches a broken caller
before anything is written, where checking the changed files alone would not
(a promotion that drops a default value breaks `Pair(1)` in another file, not
the class itself).

## Finalize

After the structural stages, the finalize passes run over the files on disk, in
a fixed order (`buildFinalizeTransformations`):

1. `fix-all` (`dart fix --apply`) first, because its fixes may remove imports.
   The lints listed under `lint_fixes:` in the config are fixed in the same
   step, with `dart fix --code=...`.
2. `organize-imports`, merged with `sort-members` when that is on so both are
   computed on one source. `sort-members` is off by default, so usually only
   `organize-imports` runs here. With `organize-imports` off, `sort-members`
   still runs on its own. It reuses the analyzer of the stages, with the files
   `dart fix` touched staged again, instead of starting a cold one.
3. `sort-constructors-first`, over the files as the previous steps left them. A
   class with a `// ignore: sort_constructors_first` comment keeps its order.
4. `dart format` last, over the files the run changed and nothing else, so a
   project formatted to another width keeps its layout everywhere the tool did
   not edit. `--no-format` (or `format` under `disabled:`) skips it, and
   `--line-length` sets the page width.

Then `--verify` runs `dart analyze` over the whole project, unchanged files
included. A new error in a changed file reverts that file; a new error in an
unchanged file reverts the changed files it depends on. Each revert can expose
another error, so the check repeats until the project is clean. The run then
reports what it kept, lists the reverted files with the passes behind them, and
exits with code 2. New warnings and infos are listed too, without reverting
anything, for projects that run `dart analyze --fatal-infos` in CI.

Copies of every file the run may rewrite go to `.dart_tool/dart_modernize/backup`
before the first write. A failure in any later step puts them back; a hard
crash leaves them for `dart_modernize --restore`.

`--dry-run` and `--check` take the same finalize steps in memory: organize
imports, sorting, and `dart format` on a scratch copy, so the diff and the
verdict cover what a real run would write. `dart fix` works only on files on
disk, so a preview lists the files it would change instead.

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
