import 'prefixed_lib.dart' as ph;

ph.Timeout defaultTimeout = ph.Timeout(30);

ph.Timeout instant = ph.Timeout.instant();

ph.Timeout make(int s) => ph.Timeout.of(s);
