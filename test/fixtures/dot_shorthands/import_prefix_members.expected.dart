import 'prefixed_lib.dart' as ph;

ph.Timeout defaultTimeout = .new(30);

ph.Timeout instant = .instant();

ph.Timeout make(int s) => .of(s);
