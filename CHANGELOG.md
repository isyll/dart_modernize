# Changelog

## 0.2.0

- **New pass: inline_return.** Inlines a local variable whose only remaining use
  is an immediate bare `return`: `final x = expr; return x;` becomes
  `return expr;`. Handles the intermediate form produced by the cascades pass
  (`var x = Obj()..a..b; return x;`) in a subsequent run.
- **Cascades reconciliation.** Removed the `_isSoleImmediateReturn` branch; the
  cascades pass now leaves `return local;` in place when local is still
  referenced, and inline_return collapses it on the next run.
- Sixteen transformation passes total (was fifteen).

## 0.1.0

- Initial scaffold.
