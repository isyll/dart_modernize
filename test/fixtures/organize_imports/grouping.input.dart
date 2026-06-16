import 'models.dart';
import 'dart:math';

Model build(int seed) {
  final coin = Random(seed).nextBool();
  return coin ? const Model() : const Model();
}
