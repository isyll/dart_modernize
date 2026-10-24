import 'geo_model.dart' as geo;

int sum() {
  final p = geo.origin();
  final x = p.x;
  final y = p.y;
  return x + y;
}
