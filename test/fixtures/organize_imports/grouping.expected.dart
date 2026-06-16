import 'dart:math';

import 'models.dart';

Model build(int seed) {
  final coin = Random(seed).nextBool();
  return coin ? const Model() : const Model();
}
