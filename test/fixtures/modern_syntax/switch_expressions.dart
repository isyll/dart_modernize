/// Already-modern switch expressions, including relational patterns.
int rank(String grade) => switch (grade) {
  'A' => 4,
  'B' => 3,
  'C' => 2,
  _ => 0,
};

String sign(int n) => switch (n) {
  < 0 => 'negative',
  0 => 'zero',
  _ => 'positive',
};
