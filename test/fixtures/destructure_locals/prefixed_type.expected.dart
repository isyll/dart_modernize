import 'geo_model.dart' as geo;

int sum() {
  final geo.Point(:x, :y) = geo.origin();
  return x + y;
}
