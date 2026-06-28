// Contextual keywords (base, when, sealed, interface, mixin) are valid ordinary
// identifiers. The passes must rewrite the surrounding code without ever
// mistaking these names for the class-modifier keywords they resemble, and the
// result must still analyze and be idempotent.

enum Channel { primary, backup }

class Router {
  final int base;

  Router(this.base);

  Channel route(int when) {
    Channel sealed = Channel.primary;
    if (when > base) {
      sealed = Channel.backup;
    }
    return sealed;
  }

  String describe(String interface) {
    final mixin = 'iface: ' + interface;
    return mixin;
  }
}
