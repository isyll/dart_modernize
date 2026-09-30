## Summary

<!-- What does this PR do and why? One paragraph max. -->

## Changes

- 

## Testing

- [ ] `dart test` passes locally
- [ ] `dart analyze --fatal-infos` passes
- [ ] `dart format $(git ls-files '*.dart' ':!test/fixtures')` produces no changes
- [ ] Dry-run tested against a real Dart project (`--dry-run`)

## Checklist

- [ ] Issue linked (closes #)
- [ ] New or modified transformations skip generated files (`*.g.dart`, `*.freezed.dart`, …)
- [ ] Transformation can be switched off (`--no-<name>`) or, if opt-in, on (`--<name>`)
- [ ] No breaking changes to public API (or CHANGELOG.md updated)
