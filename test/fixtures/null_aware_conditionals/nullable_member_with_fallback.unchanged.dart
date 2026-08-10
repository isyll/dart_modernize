// Negative: the chain's static type is nullable, so the rewrite would change
// behavior. When `box` is non-null and `box.maybe` is null the conditional
// yields null, while `box?.maybe ?? fallback` would yield the fallback.
class Box {
  String? get maybe => null;
}

String? risky(Box? box, String fallback) => box != null ? box.maybe : fallback;
