// Negative: imports are already sorted, grouped, and all used. Nothing to do.
import 'dart:async';
import 'dart:math';

Future<int> roll() async => Random().nextInt(6);
