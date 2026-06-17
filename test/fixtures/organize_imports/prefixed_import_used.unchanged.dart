// Negative: the import is used via its prefix (`math.pi`). It is already sorted
// and used, so nothing changes and it must never be pruned.
import 'dart:math' as math;

double area(double r) => math.pi * r * r;
