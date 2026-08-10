int? first(List<int>? xs) => xs == null ? null : xs[0];

int? firstReversed(List<int>? xs) => xs != null ? xs[0] : null;

int? nullFirst(List<int>? xs) => null == xs ? null : xs[0];
