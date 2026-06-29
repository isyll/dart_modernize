// Negative: class contains only constructors, so the ordering is trivially
// correct and no other members exist to trigger a reorder.
class Empty {
  Empty();

  Empty.named() : this();
}
