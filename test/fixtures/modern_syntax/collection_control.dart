/// Collection-if, collection-for, and spread elements in literals.
List<int> evens(int n) => [
  for (var i = 0; i < n; i++)
    if (i.isEven) i,
];

List<String> menu(bool includeSpecials) => [
  'soup',
  'salad',
  if (includeSpecials) ...['truffle', 'caviar'],
];

Set<int> merge(Set<int> a, Set<int> b) => {...a, ...b};
