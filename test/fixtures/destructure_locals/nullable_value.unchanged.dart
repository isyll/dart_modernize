// `p?.x` is null when `p` is; an irrefutable pattern would throw instead, and
// would not even compile on a nullable value.
import 'geo_model.dart';

int? sum() {
  final p = find(1);
  final x = p?.x;
  final y = p?.y;
  return x == null || y == null ? null : x + y;
}
