// Point is only inferred here, never imported, so `final Point(...)` would
// not compile.
import 'geo_api.dart';

int sum() {
  final p = center();
  final x = p.x;
  final y = p.y;
  return x + y;
}
